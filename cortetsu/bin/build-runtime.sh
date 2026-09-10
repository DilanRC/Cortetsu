#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
RUNTIME_ROOT="${CORTETSU_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cortetsu}"
SOURCE_BASE="$REPO/cortetsu/base"
PROVENANCE="$REPO/cortetsu/contracts/runtime-provenance.json"
BUILD_ROOT="$DATA_ROOT/builds"
STAMP="$(date +%Y%m%d-%H%M%S)-$$"
STAGING="$BUILD_ROOT/.staging-$STAMP"
FINAL="$BUILD_ROOT/$STAMP"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

require_file() {
    [[ -f "$1" ]] || fail "falta archivo requerido: $1"
}

is_managed_generation() {
    local root="$1"
    [[ -n "$root" ]] || return 1
    [[ -f "$root/shell.qml" ]] || return 1
    [[ -f "$root/BUILD_ID" ]] || return 1
    [[ -f "$root/BUILD.json" ]] || return 1
    [[ -f "$root/provenance.json" ]] || return 1
    [[ -f "$root/composition.json" ]] || return 1
}

cleanup() {
    [[ ! -d "$STAGING" ]] || rm -rf "$STAGING"
}
trap cleanup EXIT

require_file "$PROVENANCE"
require_file "$SOURCE_BASE/PROVENANCE.md"
require_file "$REPO/cortetsu/modules/BottomHub.qml"
require_file "$REPO/cortetsu/modules/CortetsuBottomHubView.qml"

mkdir -p "$BUILD_ROOT" "$RUNTIME_ROOT"
exec 9>"$DATA_ROOT/build.lock"
flock -n 9 || fail "ya hay una construcción de Cortetsu en curso"
[[ ! -e "$FINAL" ]] || fail "la generación ya existe: $FINAL"
mkdir -p "$STAGING"

printf '==> Base source-only Cortetsu\n'
cp -a "$SOURCE_BASE/." "$STAGING/"

printf '==> Módulos propios y composición\n'
cp -a "$REPO/cortetsu/modules/." "$STAGING/modules/"
cp -a "$REPO/cortetsu/shell.qml" "$STAGING/shell.qml"
mkdir -p "$STAGING/components"
cp -a "$REPO/cortetsu/components/." "$STAGING/components/"
mkdir -p "$STAGING/utils"
cp -a "$REPO/cortetsu/utils/." "$STAGING/utils/"
mkdir -p "$STAGING/services"
cp -a "$REPO/cortetsu/services/." "$STAGING/services/"
mkdir -p "$STAGING/assets/branding"
cp -a "$REPO/cortetsu/assets/branding/." "$STAGING/assets/branding/"
python3 "$REPO/cortetsu/bin/compose-panels.py" "$STAGING"
install -m 0644 "$PROVENANCE" "$STAGING/provenance.json"
install -m 0644 "$REPO/cortetsu/contracts/composition.json" "$STAGING/composition.json"

printf '==> Regresiones\n'
python3 "$REPO/scripts/features/test-native-bottom-hub.py" --runtime "$STAGING/modules/BottomHub.qml"
python3 "$REPO/scripts/features/test-bottom-hub-target.py"
python3 "$REPO/scripts/features/test-bottom-hub-v3.py"
python3 "$REPO/scripts/features/test-bottom-hub-v4.py"
python3 "$REPO/scripts/features/test-retained-overlay-wiring.py"
python3 "$REPO/scripts/features/validate-clipboard-qml.py"
python3 "$REPO/scripts/features/test-cortetsu-input-ownership.py"
python3 "$REPO/scripts/features/eval-cortetsu-input-ownership.py"
python3 "$REPO/scripts/features/test-contentwindow-overview-base.py"
python3 "$REPO/scripts/features/test-contentwindow-focusgrab-parity.py"
python3 "$REPO/scripts/features/test-wallpaper-manager.py"
python3 "$REPO/scripts/features/test-cortetsu-branding.py"
python3 "$REPO/scripts/features/test-cortetsu-evolving-branding.py"
python3 "$REPO/scripts/features/eval-cortetsu-evolving-branding.py"
python3 "$REPO/scripts/features/test-keybinds.py"
python3 "$REPO/scripts/features/test-shell-normalizer.py"
python3 "$REPO/scripts/features/test-shell-lifecycle.py"
python3 "$REPO/scripts/features/eval-shell-application-safety.py"
python3 "$REPO/scripts/features/test-first-party-surface-imports.py"
python3 "$REPO/scripts/features/eval-first-party-surface-imports.py"
bash "$REPO/cortetsu/tests/test-calendar-readonly.sh"
python3 "$REPO/cortetsu/tests/test-calendar-credentials.py"
python3 "$REPO/cortetsu/tests/test-calendar-polish.py"
python3 "$REPO/scripts/features/test-cortetsu-calendar-controls.py"
python3 "$REPO/scripts/features/eval-cortetsu-calendar-controls.py"
python3 "$REPO/scripts/features/test-cortetsu-progress-bar.py"
python3 "$REPO/scripts/features/eval-cortetsu-progress-bar.py"
python3 "$REPO/cortetsu/tests/test-pomodoro.py"
python3 "$REPO/cortetsu/tests/test-runtime-contract.py"
python3 "$REPO/scripts/features/test-cortetsu-screen-state.py"
python3 "$REPO/scripts/features/test-cortetsu-hypr-adapters.py"
python3 "$REPO/scripts/features/test-cortetsu-audio.py"
python3 "$REPO/scripts/features/test-cortetsu-network-idle.py"
python3 "$REPO/scripts/features/test-cortetsu-screenshot.py"
python3 "$REPO/scripts/features/test-package-independence.py"
python3 "$REPO/scripts/features/test-notification-backend-boundary.py"
python3 "$REPO/scripts/features/test-cortetsu-xdg-paths.py"
python3 "$REPO/scripts/features/test-cortetsu-notifications.py"
python3 "$REPO/scripts/features/test-notification-dismiss-popup.py"
python3 "$REPO/scripts/features/eval-notification-dismiss-popup.py"
python3 "$REPO/scripts/features/test-cortetsu-notification-actions.py"
python3 "$REPO/cortetsu/tests/test-notifications.py"
python3 -m py_compile "$REPO/cortetsu/bin/cortetsu-notifications"
python3 -m py_compile "$REPO/cortetsu/bin/cortetsu-record"
python3 "$REPO/scripts/features/test-cortetsu-recorder.py"
python3 "$REPO/scripts/features/test-cortetsu-config.py"
python3 "$REPO/scripts/features/test-cortetsu-idle.py"
python3 "$REPO/scripts/features/test-cortetsu-toasts.py"
python3 "$REPO/scripts/features/test-launcher-fonts.py"
python3 "$REPO/scripts/features/test-dashboard-media.py"
python3 "$REPO/scripts/features/test-dashboard-datetime.py"
python3 "$REPO/scripts/features/test-dashboard-host.py"
python3 "$REPO/scripts/features/test-dashboard-wrapper.py"
python3 "$REPO/scripts/features/test-notification-wrapper.py"
python3 "$REPO/scripts/features/test-session-host.py"
python3 "$REPO/scripts/features/test-osd-host.py"
python3 "$REPO/scripts/features/test-utilities-content.py"
python3 "$REPO/scripts/features/test-config-migration.py"
python3 "$REPO/scripts/features/test-zero-caelestia-gate.py"
python3 "$REPO/scripts/features/test-shortcut-namespace.py"
python3 "$REPO/scripts/features/test-controller-boundaries.py"
python3 "$REPO/scripts/features/test-overview-design.py"
python3 "$REPO/scripts/features/test-display-design.py"
python3 "$REPO/scripts/features/eval-cortetsu-display-controls.py"
python3 "$REPO/scripts/features/test-display-footer-layout.py"
python3 "$REPO/scripts/features/eval-display-footer-layout.py"
python3 "$REPO/scripts/features/test-display-transaction-lua.py"
python3 "$REPO/scripts/features/eval-display-transaction-lua.py"
python3 "$REPO/scripts/features/test-hardware-design.py"
python3 "$REPO/scripts/features/eval-cortetsu-hardware-tabs.py"
python3 "$REPO/scripts/features/test-wallpaper-service.py"
python3 "$REPO/scripts/features/test-cortetsu-wallpaper-palette.py"
python3 "$REPO/scripts/features/eval-cortetsu-wallpaper-palette.py"
python3 "$REPO/scripts/features/test-calendar-controller-state.py"
python3 "$REPO/scripts/features/test-cortetsu-button-tooltip.py"
python3 "$REPO/scripts/features/eval-cortetsu-button-tooltip.py"
python3 "$REPO/scripts/features/test-cortetsu-wallpaper-controls.py"
python3 "$REPO/scripts/features/eval-cortetsu-wallpaper-controls.py"
python3 "$REPO/scripts/features/test-legacy-process-migration.py"
bash -n "$REPO/cortetsu/bin/cortetsu-wallpaper-color-daemon"
bash -n "$REPO/cortetsu/bin/cortetsu-apply-wallpaper-colors"
bash -n "$REPO/cortetsu/bin/cortetsu-wallpaper-select"
python3 -m py_compile "$REPO/cortetsu/bin/cortetsu-wallpaper-colours"
bash -n "$REPO/cortetsu/bin/cortetsu-apply-wallpaper-colors"

for required in \
    shell.qml \
    modules/BottomHub.qml \
    modules/CortetsuBottomHubView.qml \
    components/ScreenState.qml \
    components/misc/CustomShortcut.qml \
    utils/NetworkConnection.qml \
    utils/Paths.qml \
    utils/Icons.qml \
    utils/CortetsuUtils.qml \
    utils/SysInfo.qml \
    modules/CortetsuModeSegment.qml \
    components/CortetsuEvolvingMark.qml \
    modules/CortetsuWorkspaceDots.qml \
    modules/CortetsuAppRail.qml \
    modules/CortetsuTraySegment.qml \
    modules/CortetsuStatusSegment.qml \
    modules/calendar/Content.qml \
    modules/calendar/Wrapper.qml \
    modules/CortetsuScreenState.qml \
    modules/CortetsuOverlayPolicy.js \
    modules/CortetsuHypr.qml \
    modules/CortetsuScreens.qml \
    modules/CortetsuConfig.qml \
    modules/CortetsuShortcut.qml \
    modules/CortetsuShellState.qml \
    services/Time.qml \
    services/Hypr.qml \
    services/Notifs.qml \
    services/NotifData.qml \
    services/CortetsuColours.qml \
    services/CortetsuTokens.qml \
    services/Brightness.qml \
    services/Audio.qml \
    services/Players.qml \
    services/Lyrics.qml \
    services/ShellState.qml \
    modules/CortetsuStateLayer.qml \
    modules/CortetsuMask.qml \
    modules/areapicker/AreaPicker.qml \
    modules/areapicker/Picker.qml \
    provenance.json \
    composition.json
do
    require_file "$STAGING/$required"
done

repo_revision="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || printf unknown)"
printf '%s\n' "$STAMP" > "$STAGING/BUILD_ID"
python3 - "$STAGING/BUILD.json" "$STAMP" "$repo_revision" <<'PY'
import json
import sys
from datetime import datetime, timezone
from pathlib import Path
path, build_id, revision = sys.argv[1:]
payload = {
    "schema": 1,
    "sourceProject": "Cortetsu",
    "buildId": build_id,
    "builtAt": datetime.now(timezone.utc).isoformat(),
    "repositoryRevision": revision,
}
Path(path).write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
PY

mv "$STAGING" "$FINAL"

atomic_link() {
    local target="$1"
    local link="$2"
    local temporary="${link}.tmp.$$"
    rm -f "$temporary"
    ln -s "$target" "$temporary"
    mv -Tf "$temporary" "$link"
}

legacy_previous="$RUNTIME_ROOT/legacy-previous"
if [[ -L "$RUNTIME_ROOT/previous" ]]; then
    existing_previous="$(readlink -f "$RUNTIME_ROOT/previous" || true)"
    if ! is_managed_generation "$existing_previous"; then
        if [[ -n "$existing_previous" && -f "$existing_previous/shell.qml" ]]; then
            atomic_link "$existing_previous" "$legacy_previous"
            printf 'WARN: previous heredado preservado como legacy-previous=%s\n' "$existing_previous"
        fi
        rm -f "$RUNTIME_ROOT/previous"
    fi
fi

previous_target=""
if [[ -L "$RUNTIME_ROOT/current" ]]; then
    previous_target="$(readlink -f "$RUNTIME_ROOT/current" || true)"
fi
if is_managed_generation "$previous_target"; then
    atomic_link "$previous_target" "$RUNTIME_ROOT/previous"
elif [[ -n "$previous_target" && -f "$previous_target/shell.qml" ]]; then
    atomic_link "$previous_target" "$legacy_previous"
    rm -f "$RUNTIME_ROOT/previous"
    printf 'WARN: runtime anterior sin metadatos Cortetsu; queda fuera del rollback automático: %s\n' "$previous_target"
fi

atomic_link "$FINAL" "$RUNTIME_ROOT/current"
[[ -f "$RUNTIME_ROOT/current/shell.qml" ]] || fail "la promoción no produjo un runtime válido"
trap - EXIT
printf 'PROMOTED current=%s\n' "$(readlink -f "$RUNTIME_ROOT/current")"
printf 'PREVIOUS previous=%s\n' "$(readlink -f "$RUNTIME_ROOT/previous" 2>/dev/null || true)"
printf 'LEGACY previous=%s\n' "$(readlink -f "$legacy_previous" 2>/dev/null || true)"
