#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLATFORM="${CORTETSU_PLATFORM:-$REPO/dist/native/cortetsu-platform}"
STAGE_ONLY=false
case "${1:-}" in
    --stage) STAGE_ONLY=true ;;
    "") ;;
    *) printf 'usage: build-runtime.sh [--stage]\n' >&2; exit 2 ;;
esac
# --stage returns only the resulting immutable path on stdout.
if "$STAGE_ONLY"; then exec 3>&1; exec 1>&2; fi
[[ "$PLATFORM" == /* && -x "$PLATFORM" ]] || { printf 'ERROR: run scripts/build-native.sh first\n' >&2; exit 1; }
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
RUNTIME_ROOT="${CORTETSU_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cortetsu}"
SOURCE_BASE="$REPO/cortetsu/base"
PROVENANCE="$REPO/cortetsu/contracts/runtime-provenance.json"
WALL_UTILITY_CONTRACT="$REPO/cortetsu/contracts/wall-utility.json"
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
require_file "$WALL_UTILITY_CONTRACT"
require_file "$SOURCE_BASE/PROVENANCE.md"
require_file "$REPO/cortetsu/modules/BottomHub.qml"
require_file "$REPO/cortetsu/modules/CortetsuBottomHubView.qml"
require_file "$REPO/cortetsu/bin/cortetsu-startup"
require_file "$REPO/cortetsu/modules/hardware/StartupPage.qml"

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
mkdir -p "$STAGING/theme"
cp -a "$REPO/cortetsu/theme/." "$STAGING/theme/"
mkdir -p "$STAGING/data"
cp -a "$REPO/cortetsu/data/." "$STAGING/data/"
mkdir -p "$STAGING/assets/branding"
cp -a "$REPO/cortetsu/assets/branding/." "$STAGING/assets/branding/"
# Cortetsu JS imports retain their source-tree ../base path after the base
# modules are flattened into the runtime root. Keep that referenced helper at
# its source-relative runtime path as well.
mkdir -p "$STAGING/base/modules/bar"
install -m 0644 "$SOURCE_BASE/modules/bar/SystemTrayIdentity.js" \
    "$STAGING/base/modules/bar/SystemTrayIdentity.js"
"$PLATFORM" compose-panels "$STAGING"
install -m 0644 "$PROVENANCE" "$STAGING/provenance.json"
install -m 0644 "$REPO/cortetsu/contracts/composition.json" "$STAGING/composition.json"
install -m 0644 "$WALL_UTILITY_CONTRACT" "$STAGING/wall-utility.json"

printf '==> Qt Quick runtime regressions\n'
qml_runner="${CORTETSU_QMLTESTRUNNER:-/usr/lib/qt6/bin/qmltestrunner}"
[[ -x "$qml_runner" ]] || fail "falta Qt Quick Test: $qml_runner"
for suite in hardware hypr surfaces calendar pomodoro polkit prompt bottomhub launcher areapicker; do
    QT_QPA_PLATFORM=offscreen timeout 300 "$qml_runner" -input "$REPO/cortetsu/tests/qml/$suite"
done

for required in \
    shell.qml \
    base/modules/bar/SystemTrayIdentity.js \
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
    modules/calendar/CalendarService.qml \
    modules/calendar/CalendarModel.js \
    modules/pomodoro/Pomodoro.qml \
    modules/pomodoro/PomodoroModel.js \
    modules/CortetsuScreenState.qml \
    modules/CortetsuOverlayPolicy.js \
    modules/OverlayPolicy.js \
    modules/SurfaceRegistry.js \
    modules/CortetsuToplevels.js \
    modules/CortetsuHypr.qml \
    modules/CortetsuHyprActions.js \
    modules/CortetsuHyprEventPolicy.js \
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
    modules/CortetsuShellInspect.js \
    modules/ShellLifecycle.qml \
    modules/CortetsuMask.qml \
    modules/areapicker/AreaPicker.qml \
    modules/areapicker/Picker.qml \
    provenance.json \
    composition.json \
    wall-utility.json
do
    require_file "$STAGING/$required"
done

# The suites above only reach the components they import. Compile the whole
# shell in Quickshell itself so a generation that would fail to load is never
# sealed or promoted.
printf '==> Quickshell compile of the complete shell\n'
"$REPO/cortetsu/bin/check-qml-compile.sh" "$STAGING" || fail "la generación no compila en Quickshell"

repo_revision="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || printf unknown)"
printf '%s\n' "$STAMP" > "$STAGING/BUILD_ID"
"$PLATFORM" build-metadata "$STAGING/BUILD.json" "$STAMP" "$repo_revision"
"$PLATFORM" seal-runtime "$STAGING"

mv "$STAGING" "$FINAL"
if "$STAGE_ONLY"; then
    trap - EXIT
    printf '%s\n' "$FINAL" >&3
    exit 0
fi


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

# The persisted scheme needs no replay: design tokens read scheme.json at
# runtime, so a new generation already shows the selected palette.
trap - EXIT
printf 'PROMOTED current=%s\n' "$(readlink -f "$RUNTIME_ROOT/current")"
printf 'PREVIOUS previous=%s\n' "$(readlink -f "$RUNTIME_ROOT/previous" 2>/dev/null || true)"
printf 'LEGACY previous=%s\n' "$(readlink -f "$legacy_previous" 2>/dev/null || true)"
