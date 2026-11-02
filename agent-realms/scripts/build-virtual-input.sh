#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output="${1:-}"
if [[ -z "$output" ]]; then
    printf 'uso: %s SALIDA\n' "$0" >&2
    exit 2
fi

for tool in wayland-scanner pkg-config; do
    command -v "$tool" >/dev/null || { printf 'falta herramienta: %s\n' "$tool" >&2; exit 1; }
done
pkg-config --exists wayland-client || { printf 'falta wayland-client de desarrollo\n' >&2; exit 1; }
compiler="${CC:-cc}"
command -v "$compiler" >/dev/null || { printf 'falta compilador C: %s\n' "$compiler" >&2; exit 1; }

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/agent-realm-input.XXXXXX")"
trap 'rm -rf -- "$build_dir"' EXIT
wayland-scanner client-header "$repo/protocols/wlr-virtual-pointer-unstable-v1.xml" \
    "$build_dir/wlr-virtual-pointer-unstable-v1-client-protocol.h"
wayland-scanner private-code "$repo/protocols/wlr-virtual-pointer-unstable-v1.xml" \
    "$build_dir/wlr-virtual-pointer-unstable-v1-protocol.c"
wayland-scanner client-header "$repo/protocols/virtual-keyboard-unstable-v1.xml" \
    "$build_dir/virtual-keyboard-unstable-v1-client-protocol.h"
wayland-scanner private-code "$repo/protocols/virtual-keyboard-unstable-v1.xml" \
    "$build_dir/virtual-keyboard-unstable-v1-protocol.c"
mkdir -p "$(dirname -- "$output")"
"$compiler" -std=c11 -O2 -Wall -Wextra -Werror \
    $(pkg-config --cflags wayland-client) -I "$build_dir" \
    "$repo/src/realm_input.c" "$build_dir/wlr-virtual-pointer-unstable-v1-protocol.c" \
    "$build_dir/virtual-keyboard-unstable-v1-protocol.c" -o "$output" $(pkg-config --libs wayland-client)
chmod 0755 "$output"
