#!/usr/bin/env bash
# Compile shell.qml and every component it reaches in the real Quickshell
# engine, without instantiating anything. qmllint and qmltestrunner miss
# engine-only errors such as "Property value set multiple times", and they
# cannot load Quickshell's plugins; this check catches both. PanelWindow needs
# a Wayland backend, so the engine runs against a private headless weston.
set -euo pipefail

usage() { printf 'usage: check-qml-compile.sh <runtime-root>\n' >&2; exit 2; }
[[ $# -eq 1 && -f "$1/shell.qml" ]] || usage
SOURCE="$(cd "$1" && pwd)"
QS="${CORTETSU_QS:-qs}"
TIMEOUT="${CORTETSU_QML_COMPILE_TIMEOUT:-60}"
command -v "$QS" >/dev/null || { printf 'ERROR: falta quickshell (%s)\n' "$QS" >&2; exit 1; }
command -v weston >/dev/null || { printf 'ERROR: falta weston para compilar QML\n' >&2; exit 1; }

# A short runtime dir keeps Quickshell's IPC socket under the sun_path limit.
WORK="$(mktemp -d /tmp/cortetsu-qmlc.XXXXXX)"
pid=""
compositor=""
cleanup() {
    local p
    for p in $pid $compositor; do kill "$p" 2>/dev/null || true; wait "$p" 2>/dev/null || true; done
    rm -rf "$WORK"
}
trap cleanup EXIT

# The shim must sit in the config root so `qs.*` imports resolve there.
cp -a "$SOURCE" "$WORK/root"
chmod -R u+w "$WORK/root"
mkdir -m 700 "$WORK/run"

# shell.qml is not a valid type name, so expose it under one. Static
# references make Quickshell scan and compile the whole tree while loading
# the shim; no Component is ever created, so no service or process starts.
# Files shell.qml loads by `source:` string are referenced here as well.
cp "$WORK/root/shell.qml" "$WORK/root/CortetsuCompileTarget.qml"
imports="" references="" n=0
while IFS= read -r path; do
    [[ -f "$WORK/root/$path" ]] || { printf 'ERROR: shell.qml carga un archivo ausente: %s\n' "$path" >&2; exit 1; }
    n=$((n + 1))
    directory="."; [[ "$path" != */* ]] || directory="${path%/*}"
    type="${path##*/}"; type="${type%.qml}"
    imports+="import \"$directory\" as Dynamic$n"$'\n'
    references+="    property Component dynamic$n: Component { Dynamic$n.$type {} }"$'\n'
done < <(grep -oE 'source: *"[^"]+\.qml"' "$WORK/root/shell.qml" | sed -E 's/^source: *"(.*)"$/\1/' || true)
cat > "$WORK/root/__cortetsu_compile_check.qml" <<QML
import QtQuick
import Quickshell
$imports
ShellRoot {
    property Component target: Component { CortetsuCompileTarget {} }
$references    Component.onCompleted: console.info("CORTETSU_COMPILE_OK")
}
QML

env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$WORK/run" \
    weston --backend=headless --socket=cortetsu-qmlc >/dev/null 2>&1 &
compositor=$!
for (( i = 0; i < 100; i++ )); do [[ -S "$WORK/run/cortetsu-qmlc" ]] && break; sleep 0.05; done
[[ -S "$WORK/run/cortetsu-qmlc" ]] || { printf 'ERROR: weston headless no arrancó\n' >&2; exit 1; }

# Quickshell ignores Qt.quit(), so wait for the verdict in its log and stop
# only the process started here.
env -i HOME="$HOME" PATH="$PATH" XDG_RUNTIME_DIR="$WORK/run" \
    WAYLAND_DISPLAY=cortetsu-qmlc QT_QPA_PLATFORM=wayland "$QS" --no-color -p "$WORK/root/__cortetsu_compile_check.qml" >/dev/null 2>&1 &
pid=$!

verdict=""
log=""
for (( i = 0; i < TIMEOUT * 4; i++ )); do
    log="$(find "$WORK/run/quickshell" -name log.log -print -quit 2>/dev/null || true)"
    if [[ -n "$log" ]]; then
        if grep -aq CORTETSU_COMPILE_OK "$log"; then verdict=ok; break; fi
        if grep -aq 'Failed to load configuration' "$log"; then verdict=fail; break; fi
    fi
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.25
done

case "$verdict" in
    ok)
        printf 'QML compile: OK (%s)\n' "$SOURCE"
        ;;
    fail)
        sleep 0.5 # let the logger flush the whole "caused by" chain
        printf 'ERROR: QML compile failed for %s\n' "$SOURCE" >&2
        # The log mixes binary framing with text; keep the error chain only.
        grep -aoE 'caused by @[^ ]+: [[:print:]]+' "$log" \
            | sed -E 's/[^[:print:]].*$//' | tail -8 >&2
        exit 1
        ;;
    *)
        printf 'ERROR: QML compile check gave no verdict within %ss\n' "$TIMEOUT" >&2
        exit 1
        ;;
esac
