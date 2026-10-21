#!/usr/bin/env bash
# Stabilization: each mutant puts back one defect this branch fixes (or breaks
# one contract it adds); the named check must fail on every one. Works on a
# scratch copy of the checkout, never on the tree itself. NESTED=1 adds the
# mutants only nested Hyprland sees (the bell scenario of stab_contracts.py).
set -euo pipefail
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
# dotfiles and config: the nested harness composes Hyprland from them.
cp -a "$repo/cortetsu" "$repo/scripts" "$repo/dotfiles" "$repo/config" "$work/"
bell() {
    timeout 900 python3 "$repo/scripts/integration/ws2_run.py" --timeout 800 "$work/bell.log" -- \
        env ONLY=bell python3 "$repo/docs/migration/stabilization/tools/stab_contracts.py" "$work" "$work/bell.json" >/dev/null 2>&1
    rm -f "$work/bell-qs.log"
    python3 -c 'import json, sys; sys.exit(any(c["result"] == "FAIL" for c in json.load(open(sys.argv[1]))["checks"]))' "$work/bell.json"
}

qml() { QT_QPA_PLATFORM=offscreen timeout 120 /usr/lib/qt6/bin/qmltestrunner -input "$work/cortetsu/tests/qml/$1" >/dev/null 2>&1; }
py() { timeout 300 python3 "$work/$1" >/dev/null 2>&1; }

failures=0
mutant() {
    local label="$1" file="$work/$2" from="$3" to="$4" backup
    shift 4
    [[ "${1:-}" == "--" ]] && shift
    backup="$(cat "$file")"
    python3 - "$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding="utf-8").read()
assert text.count(old) == 1, f"mutant anchor not found once in {path}: {old!r}"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    if "$@"; then
        printf 'SURVIVED  %s\n' "$label"; failures=$((failures + 1))
    else
        printf 'killed    %s\n' "$label"
    fi
    printf '%s' "$backup" > "$file"
}

baseline() {
    qml surfaces && qml calendar && qml pomodoro \
        && py cortetsu/tests/test-pomodoro.py && py cortetsu/tests/test-calendar-pomodoro-services.py \
        && py scripts/features/test-cortetsu-surface-registry.py && py scripts/features/test-contentwindow-focusgrab-parity.py \
        && py scripts/features/test-retained-surfaces-host.py && py cortetsu/tests/test-calendar-polish.py \
        && py scripts/features/test-cortetsu-keyboards-runtime.py \
        && { [[ "${NESTED:-0}" != 1 ]] || bell; }
}
baseline || { echo "baseline does not pass"; exit 2; }

P=cortetsu/modules/CortetsuOverlayPolicy.js
mutant "O-1: open closes only its own screen" $P \
    '        closeExclusiveEverywhere(states);
    return Exclusion.setFlag(target, flag, true);' '        Exclusion.closeOtherPanels(target);
    return Exclusion.setFlag(target, flag, true);' -- qml surfaces
mutant "retained toggle acts per screen" $P \
    'if (isRetainedFlag(flag) && openAnywhere(states, flag)) {' 'if (false) {' -- qml surfaces
mutant "fullscreen also blocks closing" $P \
    'if (fullscreen && Surfaces.isFullscreenGuarded(flag) && !isOpen(target, flag))' 'if (fullscreen && Surfaces.isFullscreenGuarded(flag))' -- qml surfaces
mutant "sidebar no longer guarded under fullscreen" cortetsu/modules/SurfaceRegistry.js \
    '{ name: "sidebar", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: true }' \
    '{ name: "sidebar", kind: "transient", exclusive: true, ownsKeyboard: false, fullscreenGuard: false }' -- qml surfaces
mutant "O-2: SUPER+N writes the flag itself again" cortetsu/modules/Shortcuts.qml \
    'onPressed: root.toggleSurface(CortetsuShellState.forActive(), "sidebar")' \
    'onPressed: { const s = CortetsuShellState.forActive(); s.sidebar = !s.sidebar; }' -- py scripts/features/test-cortetsu-surface-registry.py
mutant "O-1: calendar controller with its own open again" cortetsu/modules/CalendarController.qml \
    'RetainedSurfaceController {' 'Scope { function open() { CortetsuShellState.forActive().cortetsuState.setRetained("calendar", true) }
    RetainedSurfaceController {' -- py scripts/features/test-cortetsu-surface-registry.py
mutant "O-3: drawer window drops to none under the grab" cortetsu/modules/drawers/ContentWindow.qml \
    ': (panels.popouts.hasCurrent || wantsFocusGrab' ': (panels.popouts.hasCurrent' -- py scripts/features/test-contentwindow-focusgrab-parity.py
mutant "second keyboard-mode writer (focusable) is back" cortetsu/modules/drawers/ContentWindow.qml \
    '    name: "drawers"' '    name: "drawers"
    focusable: panels.popouts.hasCurrent' -- py scripts/features/test-contentwindow-focusgrab-parity.py
mutant "hidden Calendar copy in the drawer window" cortetsu/modules/drawers/Panels.qml \
    '    Dashboard.Wrapper {' '    Calendar.Wrapper { visible: false; screenState: root.screenState }
    Dashboard.Wrapper {' -- py scripts/features/test-retained-surfaces-host.py
mutant "Pomodoro reset wipes the user's durations" cortetsu/bin/cortetsu-pomodoro \
    'state = {**DEFAULT, **{key: state[key] for key in CONFIG_KEYS}}' 'state = {**DEFAULT}' -- py cortetsu/tests/test-pomodoro.py
mutant "a command's phase end is not announced" cortetsu/bin/cortetsu-pomodoro \
    '        if transition:
            write_event(*transition)' '        pass' -- py cortetsu/tests/test-pomodoro.py
mutant "daemon polls every 0.5 s again" cortetsu/bin/cortetsu-pomodoro \
    'deadline.wait(state["targetEndTimestamp"] if running else None, wake_read)' 'time.sleep(0.5)' -- py cortetsu/tests/test-pomodoro.py
mutant "clock set back leaves more than a phase" cortetsu/bin/cortetsu-pomodoro \
    '    if target - current_time > duration:' '    if False:' -- py cortetsu/tests/test-pomodoro.py
mutant "running phase without deadline sticks" cortetsu/bin/cortetsu-pomodoro \
    'if state["phase"] in ACTIVE_PHASES and not state["targetEndTimestamp"]:' 'if False:' -- py cortetsu/tests/test-pomodoro.py
mutant "a reload repeats the last toast" cortetsu/modules/pomodoro/PomodoroModel.js \
    'toast: fresh && sequence > startedNs' 'toast: fresh' -- qml pomodoro
mutant "countdown floors to 00:00 early" cortetsu/modules/pomodoro/PomodoroModel.js \
    'const seconds = Math.ceil(remainingMs(state, nowMs) / 1000);' 'const seconds = Math.floor(remainingMs(state, nowMs) / 1000);' -- qml pomodoro
mutant "event cache read without reload" cortetsu/modules/calendar/CalendarService.qml \
    '        onLoaded: root.payload = root.parse(text())
        onLoadFailed: root.payload = ({})
        onFileChanged: reload()' '        onLoaded: root.payload = root.parse(text())
        onLoadFailed: root.payload = ({})
        onFileChanged: root.payload = root.parse(text())' -- py cortetsu/tests/test-calendar-pomodoro-services.py
mutant "state file read without reload" cortetsu/modules/pomodoro/Pomodoro.qml \
    '        onLoaded: root.state = root.parse(text()) ?? {}
        onLoadFailed: root.state = ({})
        onFileChanged: reload()' '        onLoaded: root.state = root.parse(text()) ?? {}
        onLoadFailed: root.state = ({})
        onFileChanged: root.state = root.parse(text()) ?? {}' -- py cortetsu/tests/test-calendar-pomodoro-services.py
mutant "all-day end treated as inclusive" cortetsu/modules/calendar/CalendarModel.js \
    'return new Date(end.getTime() - 1);' 'return end;' -- qml calendar
mutant "events of the same month in another year" cortetsu/modules/calendar/CalendarModel.js \
    'day.getMonth() === month && day.getFullYear() === year;' 'day.getMonth() === month;' -- qml calendar
H=cortetsu/modules/RetainedSurfacesHost.qml
mutant "bell: a panel over the bell no longer keeps the click" cortetsu/modules/ScrimHit.js \
    'if (child.width < container.width || child.height < container.height)' 'if (false)' -- qml surfaces
mutant "bell: a Keyboards capture no longer blocks the click" $H \
    'return !keyboards.dismissBlocked' 'return true' -- py scripts/features/test-retained-surfaces-host.py
mutant "bell: recording no longer blocks pointer dismissal" cortetsu/modules/keyboards/Content.qml \
    'readonly property bool pointerDismissBlocked: listening || Flow.busy(flow)' \
    'readonly property bool pointerDismissBlocked: Flow.busy(flow)' -- py scripts/features/test-cortetsu-keyboards-runtime.py
if [[ "${NESTED:-0}" == 1 ]]; then
    mutant "bell: the scrim only dismisses again (63bb651)" $H \
        'onPressed: mouse => mouse.accepted = window.reachesBell(mouse.x, mouse.y)' 'onPressed: mouse => mouse.accepted = false' -- bell
    mutant "bell: the click is taken over a panel" $H \
        '                    && ScrimHit.backdropOnly(surfaces, x, y);' '                    ;' -- bell
    mutant "bell: forwarded over Overview too" $H \
        'enabled: window.surfaceOpen && !(window.screenState?.cortetsuState?.overview ?? false)' 'enabled: window.surfaceOpen' -- bell
fi
[[ $failures -eq 0 ]] && echo "all mutants killed" || { echo "$failures mutant(s) survived"; exit 1; }
