#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
RUNTIME_ROOT="${CORTETSU_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cortetsu}"

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

atomic_link() {
    local target="$1"
    local link="$2"
    local temporary="${link}.tmp.$$"
    rm -f "$temporary"
    ln -s "$target" "$temporary"
    mv -Tf "$temporary" "$link"
}

is_managed_generation() {
    local root="$1"
    local required
    [[ -n "$root" ]] || return 1
    for required in \
        shell.qml \
        BUILD_ID \
        BUILD.json \
        provenance.json \
        composition.json \
        modules/BottomHub.qml \
        modules/calendar/Content.qml \
        modules/calendar/Wrapper.qml
    do
        [[ -f "$root/$required" ]] || return 1
    done
}

mkdir -p "$DATA_ROOT" "$RUNTIME_ROOT"
exec 9>"$DATA_ROOT/build.lock"
flock -n 9 || fail "hay una construcción o rollback de Cortetsu en curso"

[[ -L "$RUNTIME_ROOT/current" ]] || fail "no existe el enlace current"
[[ -L "$RUNTIME_ROOT/previous" ]] || fail "no existe una generación previous administrada"
current="$(readlink -f "$RUNTIME_ROOT/current" || true)"
previous="$(readlink -f "$RUNTIME_ROOT/previous" || true)"

is_managed_generation "$current" || fail "current no es una generación Cortetsu administrada: $current"
is_managed_generation "$previous" || fail "previous no es una generación Cortetsu administrada: $previous; ejecuta cortetsu install para reemplazar el destino heredado"
[[ "$current" != "$previous" ]] || fail "current y previous apuntan a la misma generación"

atomic_link "$previous" "$RUNTIME_ROOT/current"
atomic_link "$current" "$RUNTIME_ROOT/previous"
[[ "$(readlink -f "$RUNTIME_ROOT/current")" == "$previous" ]] || fail "falló la conmutación atómica"
printf 'ROLLED BACK current=%s previous=%s\n' "$previous" "$current"
