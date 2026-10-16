#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
export CORTETSU_DATA_ROOT="$DATA_ROOT"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
# Retired: keep-awake is now a shell toggle (CortetsuIdleInhibitor), not a unit.
KEEP_AWAKE_UNIT="cortetsu-keep-awake.service"
WALLPAPER_COLOR_UNIT="cortetsu-wallpaper-color.service"

atomic_symlink() {
    local target="$1"
    local link="$2"
    local temporary="${link}.tmp.$$"
    rm -f "$temporary"
    ln -s "$target" "$temporary"
    mv -Tf "$temporary" "$link"
}

mkdir -p "$DATA_ROOT"
# Held for the whole install so an explicit GC cannot run against a
# half-promoted system; GC takes this lock without waiting and refuses.
exec 8>>"$DATA_ROOT/install.lock"
flock -n 8 || { printf 'ERROR: ya hay una instalación de Cortetsu en curso\n' >&2; exit 1; }

legacy_state_present=0
for legacy_candidate in \
    "${XDG_CONFIG_HOME:-$HOME/.config}/caelestia" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/caelestia" \
    "${XDG_CACHE_HOME:-$HOME/.cache}/caelestia" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia" \
    "${XDG_CONFIG_HOME:-$HOME/.config}/caerice" \
    "${XDG_STATE_HOME:-$HOME/.local/state}/caerice"; do
    if [[ -e "$legacy_candidate" ]]; then
        legacy_state_present=1
        break
    fi
done
if [[ "$legacy_state_present" == 1 && -x "$REPO/scripts/migrate-cortetsu-v2.sh" ]]; then
    "$REPO/scripts/migrate-cortetsu-v2.sh"
else
    printf 'Migración legacy: no hay estado anterior; se omite.\n'
fi

printf '==> Cortetsu: validación y construcción aislada\n'
"$REPO/cortetsu/bin/check-package-updates.sh" || true
"$REPO/cortetsu/bin/build-runtime.sh"

printf '==> Helpers Cortetsu\n'
mkdir -p "$BIN_DIR" "$DATA_ROOT"
while IFS= read -r -d '' source; do
    name="$(basename "$source")"
    install -m 0755 "$source" "$BIN_DIR/$name"
done < <(find "$REPO/cortetsu/bin" -maxdepth 1 -type f -name 'cortetsu-*' -print0 | sort -z)

mkdir -p "$SYSTEMD_USER_DIR"
install -m 0644 "$REPO/config/systemd/user/$WALLPAPER_COLOR_UNIT" "$SYSTEMD_USER_DIR/$WALLPAPER_COLOR_UNIT"

# The pre-Cortetsu nvibrant.service runs a bare `nvibrant 128` at login and
# would overwrite the profile that cortetsu-nvibrant reapplies from Hyprland.
if systemctl --user is-enabled --quiet nvibrant.service 2>/dev/null; then
    systemctl --user disable nvibrant.service >/dev/null 2>&1 || true
    printf 'nvibrant.service desactivada; Cortetsu reaplica la vibrance. Revertir: systemctl --user enable nvibrant.service\n'
fi

# Low-level shell rollback remains available for recovery. Normal operation uses
# `cortetsu rollback`, which reverts the full system generation.
install -m 0755 "$REPO/cortetsu/bin/rollback-runtime.sh" "$BIN_DIR/cortetsu-rollback"
install -m 0755 "$REPO/cortetsu/bin/cortetsu-scheme" "$BIN_DIR/cortetsu-scheme"

if [[ -x "$REPO/scripts/cortetsu" ]]; then
    atomic_symlink "$REPO" "$DATA_ROOT/repository"
    atomic_symlink "$REPO/scripts/cortetsu" "$BIN_DIR/cortetsu"
fi

printf '==> Tema nativo Cortetsu\n'
python3 "$REPO/core/theme.py" check --repo "$REPO"

printf '==> Ownership de tema\n'
python3 "$REPO/core/theme.py" adopt --repo "$REPO"

printf '==> Dotfiles Cortetsu\n'
python3 "$REPO/core/dotfiles.py" apply --repo "$REPO"

printf '==> Retiro de tema heredado\n'
python3 "$REPO/scripts/maintenance/retire_legacy_theme.py"

printf '==> Ciclo de vida del shell\n'
python3 "$REPO/core/shell_lifecycle.py" migrate

systemctl --user daemon-reload >/dev/null 2>&1 || true

source "$REPO/scripts/lib/notification-owner.sh"
mask_rival_notification_daemon

# The old unit held a permanent sleep:idle block inhibitor, so CanSuspend was
# "inhibited" and the session menu's Suspend did nothing. Keep-awake is now
# off by default and toggled from BottomHub, Settings, IPC or SUPER+ALT+K.
if systemctl --user is-enabled --quiet "$KEEP_AWAKE_UNIT" 2>/dev/null \
        || systemctl --user is-active --quiet "$KEEP_AWAKE_UNIT" 2>/dev/null; then
    systemctl --user disable --now "$KEEP_AWAKE_UNIT" >/dev/null 2>&1 || true
    if systemctl --user is-active --quiet "$KEEP_AWAKE_UNIT" 2>/dev/null; then
        printf 'WARN: %s sigue activa; detenla con systemctl --user stop %s\n' "$KEEP_AWAKE_UNIT" "$KEEP_AWAKE_UNIT" >&2
    else
        printf 'Keep awake: unidad permanente retirada; ahora es un interruptor del shell\n'
    fi
fi
if [[ -f "$SYSTEMD_USER_DIR/$KEEP_AWAKE_UNIT" ]]; then
    mv -f "$SYSTEMD_USER_DIR/$KEEP_AWAKE_UNIT" "$SYSTEMD_USER_DIR/$KEEP_AWAKE_UNIT.retired"
    systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

if [[ "$(systemctl --user show -p Transient --value "$WALLPAPER_COLOR_UNIT" 2>/dev/null || true)" == "yes" ]]; then
    systemctl --user stop "$WALLPAPER_COLOR_UNIT" >/dev/null 2>&1 || true
fi
if systemctl --user enable --now "$WALLPAPER_COLOR_UNIT" >/dev/null 2>&1; then
    printf 'Wallpaper colors: active and enabled\n'
else
    printf 'WARN: no se pudo activar %s\n' "$WALLPAPER_COLOR_UNIT" >&2
fi

# Preserve the user's explicit opt-in when migrating the renamed power service.
if [[ -f "$DATA_ROOT/.power-auto-was-enabled" && -f "$SYSTEMD_USER_DIR/cortetsu-power-auto.service" ]]; then
    if systemctl --user enable --now cortetsu-power-auto.service >/dev/null 2>&1; then
        rm -f "$DATA_ROOT/.power-auto-was-enabled"
        printf 'Power automation: opt-in restored\n'
    else
        printf 'WARN: no se pudo reactivar cortetsu-power-auto.service; el marcador se conserva\n' >&2
    fi
fi

printf '==> Generación unificada Cortetsu\n'
python3 "$REPO/core/system.py" promote --repo "$REPO"

printf '==> Verificación completa del sistema promovido\n'
"$REPO/scripts/cortetsu" verify
# Installation never deletes generations. The report below is computed after
# promotion, so it names exactly what an explicit `cortetsu gc --apply` would
# remove now; the user decides whether to run it.
printf '==> Generaciones (solo inspección, no se borra nada)\n'
"$REPO/scripts/cortetsu" gc --keep 5 | grep -E '^(TOTAL_DELETE|TOTAL_RECLAIM|PLAN_ID|  DELETE)' || true
printf 'Detalle y aplicación explícita: cortetsu gc\n'

# Never restart shell supervision implicitly. The promoted generation is safe
# to adopt on an explicit soft reload that keeps the process alive. Persistent
# application launches use independent user scopes, so an explicit hard shell
# lifecycle operation does not own or terminate those applications.
if systemctl --user is-enabled --quiet cortetsu-shell.service 2>/dev/null; then
    printf 'Shell supervision: no se reinicia automáticamente; se conserva el escritorio abierto\n'
    printf 'Para adoptar el runtime sin cerrar el proceso: cortetsu shell reload\n'
    printf 'Mantenimiento duro: disponible de forma explícita; las aplicaciones persistentes usan scopes independientes\n'
fi

runtime_root="${CORTETSU_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cortetsu}"
printf '\nCortetsu runtime: %s/current\n' "$runtime_root"
printf 'Dotfiles runtime: %s/dotfiles/current\n' "$DATA_ROOT"
printf 'System runtime: %s/system/current\n' "$DATA_ROOT"
printf 'No se escribió ningún runtime legacy de Caelestia.\n'
printf 'Tema desktop: ui.toml -> CortetsuDesign/Kitty/GTK/KDE; kdeglobals permanece editable.\n'
printf 'Shell personal: Fish es dependencia del perfil personal y se importa de forma explícita con core/import_fish.py.\n'
printf 'cortetsu-shell.service no se habilita implícitamente; una adopción existente sí se conserva.\n'
printf 'Rollback completo: cortetsu rollback\n'
printf 'Supervisión: cortetsu shell status\n'
