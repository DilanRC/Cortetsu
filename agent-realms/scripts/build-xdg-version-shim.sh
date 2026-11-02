#!/usr/bin/env bash
set -euo pipefail

repo="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
output="${1:-}"
if [[ -z "$output" ]]; then
    printf 'uso: %s SALIDA\n' "$0" >&2
    exit 2
fi

for tool in pkg-config; do
    command -v "$tool" >/dev/null || { printf 'falta herramienta: %s\n' "$tool" >&2; exit 1; }
done
pkg-config --exists wayland-server || { printf 'faltan headers y biblioteca wayland-server\n' >&2; exit 1; }
compiler="${CC:-cc}"
command -v "$compiler" >/dev/null || { printf 'falta compilador C: %s\n' "$compiler" >&2; exit 1; }
mkdir -p "$(dirname -- "$output")"
"$compiler" -std=c11 -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$repo/src/xdg-version-shim.c" \
    $(pkg-config --cflags wayland-server) \
    -o "$output" $(pkg-config --libs wayland-server) -ldl
chmod 0700 "$output"
