#!/usr/bin/env bash
# F1a: each mutant breaks one contract of the surface registry; the runtime
# test (tst_SurfaceRegistry.qml) or the static gate must fail on every one.
# Works on a scratch copy of the checkout, never on the tree itself.
set -euo pipefail
repo="$(cd "$(dirname "$0")/../../../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cp -a "$repo/cortetsu" "$repo/scripts" "$work/"

qml() { QT_QPA_PLATFORM=offscreen timeout 60 /usr/lib/qt6/bin/qmltestrunner -input "$work/cortetsu/tests/qml/surfaces" >/dev/null 2>&1; }
gate() { python3 "$work/scripts/features/test-cortetsu-surface-registry.py" >/dev/null 2>&1; }

failures=0
mutant() {
    local label="$1" check="$2" file="$work/$3" from="$4" to="$5" backup
    backup="$(cat "$file")"
    python3 - "$file" "$from" "$to" <<'PY'
import sys
path, old, new = sys.argv[1:]
text = open(path, encoding="utf-8").read()
assert text.count(old) == 1, f"mutant anchor not found once in {path}: {old!r}"
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    if "$check"; then
        printf 'SURVIVED  %s\n' "$label"; failures=$((failures + 1))
    else
        printf 'killed    %s\n' "$label"
    fi
    printf '%s' "$backup" > "$file"
}

qml && gate || { echo "baseline does not pass"; exit 2; }
R=cortetsu/modules/SurfaceRegistry.js
mutant "osd becomes exclusive" qml $R '{ name: "osd", kind: "transient", exclusive: false' '{ name: "osd", kind: "transient", exclusive: true'
mutant "keyboards dropped from the registry" qml $R '    { name: "keyboards", kind: "retained", exclusive: true, ownsKeyboard: true, ipcExclusive: false },
' ''
mutant "settings owns the keyboard (old ScreenState copy)" qml $R '{ name: "settings", kind: "transient", exclusive: true, ownsKeyboard: false' '{ name: "settings", kind: "transient", exclusive: true, ownsKeyboard: true'
mutant "wallpaper not spared by closeForWallpaper" qml $R 'entry.exclusive && entry.name !== "wallpaperManager"' 'entry.exclusive'
mutant "policy writes around setFlag" qml cortetsu/modules/OverlayPolicy.js 'if (typed && typeof typed.setFlag === "function")' 'if (false)'
mutant "hasCompetingPanel blind to the typed state" qml cortetsu/modules/OverlayPolicy.js 'state?.legacyState ?? state, Surfaces.competingWithWallpaper' 'state, Surfaces.competingWithWallpaper'
mutant "setFlag accepts unknown names" qml cortetsu/modules/CortetsuScreenState.qml 'if (!Surfaces.isSettable(flag) || legacyState[flag] === undefined)' 'if (legacyState[flag] === undefined)'
mutant "openExclusive skips closeAll" qml cortetsu/modules/CortetsuOverlayPolicy.js '    closeAll(state);
    return' '    return'
mutant "Shortcuts keeps its own list again" gate cortetsu/modules/Shortcuts.qml 'if (root.hasFullscreen && Surfaces.isIpcExclusive(target)) return;' 'if (root.hasFullscreen && ["launcher", "session"].includes(target)) return;'
mutant "ScreenState declares an unregistered flag" gate cortetsu/components/ScreenState.qml '    property bool keyboards' '    property bool keyboards
    property bool lockscreen'
mutant "ScreenState derives input flags again" gate cortetsu/components/ScreenState.qml '    // Derived input/layer flags live only in cortetsuState.' '    readonly property bool requiresFullInputMask: overview'
mutant "a module hard-codes a surface list" gate cortetsu/modules/BottomHub.qml '    function closeAllLaunchers(): void {' '    readonly property var stacked: ["hardware", "clipboard"]
    function closeAllLaunchers(): void {'
[[ $failures -eq 0 ]] && echo "all mutants killed" || { echo "$failures mutant(s) survived"; exit 1; }
