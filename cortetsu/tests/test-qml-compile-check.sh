#!/usr/bin/env bash
# The build gate must reject an engine-only QML error that qmllint accepts.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECK="$REPO/cortetsu/bin/check-qml-compile.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/ok" "$WORK/bad"
printf 'import QtQuick\nimport Quickshell\nShellRoot { Item { x: 1 } }\n' > "$WORK/ok/shell.qml"
# Same shape as the clipboard regression: one property assigned twice.
printf 'import QtQuick\nimport Quickshell\nShellRoot { Item {\n x: 1\n x: 1\n } }\n' > "$WORK/bad/shell.qml"

"$CHECK" "$WORK/ok" >/dev/null
if output="$("$CHECK" "$WORK/bad" 2>&1)"; then
    printf 'FAIL: duplicated property compiled\n' >&2; exit 1
fi
grep -q 'Property value set multiple times' <<<"$output" \
    || { printf 'FAIL: unexpected diagnostic:\n%s\n' "$output" >&2; exit 1; }

# A file shell.qml loads only through Loader.source must be compiled too.
mkdir -p "$WORK/dynamic/modules"
printf 'import QtQuick\nimport Quickshell\nShellRoot { Loader { active: false; source: "modules/Late.qml" } }\n' \
    > "$WORK/dynamic/shell.qml"
printf 'import QtQuick\nItem {\n y: 1\n y: 1\n}\n' > "$WORK/dynamic/modules/Late.qml"
if output="$("$CHECK" "$WORK/dynamic" 2>&1)"; then
    printf 'FAIL: broken Loader.source target compiled\n' >&2; exit 1
fi
grep -q 'Late.qml.*Property value set multiple times' <<<"$output" \
    || { printf 'FAIL: unexpected Loader diagnostic:\n%s\n' "$output" >&2; exit 1; }
printf 'import QtQuick\nItem { y: 1 }\n' > "$WORK/dynamic/modules/Late.qml"
"$CHECK" "$WORK/dynamic" >/dev/null
printf 'QML compile check: PASS\n'
