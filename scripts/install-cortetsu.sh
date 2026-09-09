#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${HOME}/.local/bin"
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
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
install -m 0644 "$REPO/config/systemd/user/$KEEP_AWAKE_UNIT" "$SYSTEMD_USER_DIR/$KEEP_AWAKE_UNIT"
install -m 0644 "$REPO/config/systemd/user/$WALLPAPER_COLOR_UNIT" "$SYSTEMD_USER_DIR/$WALLPAPER_COLOR_UNIT"

# Low-level shell rollback remains available for recovery. Normal operation uses
# `cortetsu rollback`, which reverts the full system generation.
install -m 0755 "$REPO/cortetsu/bin/rollback-runtime.sh" "$BIN_DIR/cortetsu-rollback"

if [[ -x "$REPO/scripts/cortetsu" ]]; then
    atomic_symlink "$REPO" "$DATA_ROOT/repository"
    atomic_symlink "$REPO/scripts/cortetsu" "$BIN_DIR/cortetsu"
fi

printf '==> Tema nativo Cortetsu\n'
python3 "$REPO/core/theme.py" check --repo "$REPO"

printf '==> Dotfiles Cortetsu\n'
python3 "$REPO/core/dotfiles.py" apply --repo "$REPO"

printf '==> Retiro de tema heredado\n'
python3 "$REPO/scripts/maintenance/retire_legacy_theme.py"

printf '==> Ciclo de vida del shell\n'
python3 "$REPO/core/shell_lifecycle.py" migrate

printf '==> Ownership de tema\n'
python3 "$REPO/core/theme.py" adopt --repo "$REPO"

systemctl --user daemon-reload >/dev/null 2>&1 || true

# Keep-awake is an explicit user requirement and must survive each promoted
# generation. The unit is scoped to this user session and uses systemd's
# inhibitor API, never a global desktop setting.
if systemctl --user enable --now "$KEEP_AWAKE_UNIT" >/dev/null 2>&1; then
    printf 'Keep awake: active and enabled\n'
else
    printf 'WARN: no se pudo activar %s\n' "$KEEP_AWAKE_UNIT" >&2
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

# Never restart shell supervision implicitly. Restarting Quickshell tears down
# its StatusNotifier host; the installed ChatGPT Desktop Electron build has
# crashed with SIGTRAP when that tray peer disappears. The promoted generation
# is safe to adopt on an explicit, guarded shell restart.
if systemctl --user is-enabled --quiet cortetsu-shell.service 2>/dev/null; then
    printf 'Shell supervision: no se reinicia automáticamente; se conserva el escritorio abierto\n'
    printf 'Para adoptar el runtime explícitamente: CORTETSU_RESTART_SHELL=1 cortetsu shell restart\n'
fi

runtime_root="${CORTETSU_RUNTIME_ROOT:-${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/cortetsu}"
printf '\nCortetsu runtime: %s/current\n' "$runtime_root"
printf 'Dotfiles runtime: %s/dotfiles/current\n' "$DATA_ROOT"
printf 'System runtime: %s/system/current\n' "$DATA_ROOT"
printf 'No se escribió ningún runtime legacy de Caelestia.\n'
printf 'Tema desktop: ui.toml -> CortetsuDesign/Kitty/GTK/KDE; Caelestia queda sin ownership de esas superficies.\n'
printf 'Shell personal: Fish es dependencia del perfil personal y se importa de forma explícita con core/import_fish.py.\n'
printf 'cortetsu-shell.service no se habilita implícitamente; una adopción existente sí se conserva.\n'
printf 'Rollback completo: cortetsu rollback\n'
printf 'Supervisión: cortetsu shell status\n'
