#!/usr/bin/env bash
# Installs the SDDM greeter compositor launcher (config/sddm) system-wide.
# Run as root: sudo scripts/install-sddm-greeter.sh   (undo with --remove)
#
# /etc/sddm.conf wins over /etc/sddm.conf.d, so the CompositorCommand line is
# rewritten there; the previous file is kept next to it.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${CORTETSU_SYSTEM_ROOT:-}"
CONF="$ROOT/etc/sddm.conf"
TARGET="$ROOT/usr/local/lib/cortetsu/sddm-greeter-compositor"
# The path SDDM runs, without the test prefix.
COMMAND_PATH="/usr/local/lib/cortetsu/sddm-greeter-compositor"

[[ -n "$ROOT" || $EUID -eq 0 ]] || { echo "ERROR: ejecuta con sudo" >&2; exit 1; }
[[ -f "$CONF" ]] || { echo "ERROR: no existe $CONF" >&2; exit 1; }
current="$(sed -n 's/^CompositorCommand=//p' "$CONF")"
[[ -n "$current" ]] || { echo "ERROR: $CONF no define CompositorCommand; el saludo no usa Wayland" >&2; exit 1; }

if [[ "${1:-}" == --remove ]]; then
    case "$current" in
        "$COMMAND_PATH "*) sed -i "s|^CompositorCommand=$COMMAND_PATH |CompositorCommand=weston |" "$CONF" ;;
    esac
    rm -f "$TARGET"
    echo "Restaurado: $(grep '^CompositorCommand=' "$CONF")"
    exit 0
fi

install -D -m 0755 "$REPO/config/sddm/cortetsu-greeter-compositor" "$TARGET"
case "$current" in
    "$COMMAND_PATH "*) ;;
    "weston "*)
        cp -p "$CONF" "$CONF.cortetsu-backup"
        sed -i "s|^CompositorCommand=weston |CompositorCommand=$COMMAND_PATH |" "$CONF"
        ;;
    *) echo "ERROR: CompositorCommand no es weston: $current" >&2; exit 1 ;;
esac
echo "Instalado: $(grep '^CompositorCommand=' "$CONF")"
echo "Se aplica en el próximo arranque de SDDM (reinicio o cierre de sesión)."
