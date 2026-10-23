#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
export CORTETSU_DATA_ROOT="$DATA_ROOT"
SYSTEMD_USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
KEEP_AWAKE_UNIT="cortetsu-keep-awake.service"
WALLPAPER_COLOR_UNIT="cortetsu-wallpaper-color.service"
native_input=""
if [[ "${1:-}" == --native-bundle && $# == 2 ]]; then
    native_input="$2"
    [[ "$native_input" == /* && -d "$native_input" && ! -L "$native_input" ]] || { printf 'ERROR: --native-bundle requires an absolute directory\n' >&2; exit 2; }
elif [[ $# != 0 ]]; then
    printf 'usage: install-cortetsu.sh [--native-bundle ABSOLUTE_DIRECTORY]\n' >&2
    exit 2
fi


# Each installation builds its own staging directory. Concurrent compilers
# cannot change the resource pointer of a bundle about to be hashed.
mkdir -p "$REPO/dist"
native_output="$(mktemp -d "$REPO/dist/.install-native-XXXXXXXX")"
stage_report="$(mktemp)"
PLATFORM="$native_output/cortetsu-platform"
RESCUE="$native_output/cortetsu-rescue"
transaction_active=0
cleanup() {
    local status=$? keep_native=0
    trap - EXIT
    if [[ "$transaction_active" == 1 ]]; then
        printf 'Instalación interrumpida: restaurando la generación y los ficheros anteriores.\n' >&2
        if ! "$PLATFORM" install-transaction recover; then
            printf 'ERROR: la recuperación no pudo completarse; conserva el journal y ejecuta cortetsu recover.\n' >&2
            status=1
            keep_native=1
            printf 'Recovery tool retained: %s\n' "$PLATFORM" >&2
        fi
    fi
    rm -f -- "$stage_report"
    if [[ "$keep_native" == 0 ]]; then rm -rf -- "$native_output"; fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '==> Runtime nativo Cortetsu\n'
if [[ -n "$native_input" ]]; then
    while IFS= read -r -d '' artifact; do
        [[ -f "$artifact" && ! -L "$artifact" && -x "$artifact" ]] || { printf 'ERROR: unsafe native bundle entry: %s\n' "$artifact" >&2; exit 1; }
    done < <(find "$native_input" -mindepth 1 -maxdepth 1 -print0)
    cp -a "$native_input/." "$native_output/"
else
    CORTETSU_NATIVE_OUTPUT="$native_output" "$REPO/scripts/build-native.sh"
fi
[[ -x "$PLATFORM" && -x "$RESCUE" && -x "$native_output/cortetsu" ]] || { printf 'ERROR: native bundle is incomplete\n' >&2; exit 1; }

printf '==> Construcción y validación aislada del shell\n'
shell_generation="$(CORTETSU_PLATFORM="$PLATFORM" "$REPO/cortetsu/bin/build-runtime.sh" --stage)"
[[ -d "$shell_generation" ]] || { printf 'ERROR: shell staging produced no generation\n' >&2; exit 1; }
# Pin helper data to the matching immutable shell generation. This helper is
# hashed with the rest of the bundle before any active pointer changes.
{
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %q\n' "$shell_generation"
} > "$native_output/cortetsu-resource-root"
chmod 0755 "$native_output/cortetsu-resource-root"
"$RESCUE" helpers-stage "$native_output" > "$stage_report"
helpers_generation="$("$PLATFORM" metadata "$stage_report" bundle.directory)"
[[ -d "$helpers_generation" ]] || { printf 'ERROR: helper staging produced no generation\n' >&2; exit 1; }


mkdir -p "$DATA_ROOT"
[[ ! -L "$DATA_ROOT/install.lock" ]] || { printf 'ERROR: install.lock is a symlink\n' >&2; exit 1; }
exec 8>>"$DATA_ROOT/install.lock"
flock -n 8 || { printf 'ERROR: ya hay una instalación de Cortetsu en curso\n' >&2; exit 1; }
"$PLATFORM" install-transaction recover
CORTETSU_INSTALL_TRANSACTION="$("$PLATFORM" install-transaction begin --repo "$REPO" --helpers "$helpers_generation" --shell "$shell_generation")"
export CORTETSU_INSTALL_TRANSACTION
transaction_active=1
"$PLATFORM" install-transaction activate

printf '==> Tema nativo y ownership\n'
"$PLATFORM" theme check --repo "$REPO"
"$PLATFORM" theme adopt --repo "$REPO"
printf '==> Dotfiles Cortetsu\n'
"$PLATFORM" dotfiles apply --repo "$REPO"
printf '==> Retiro de tema heredado y ciclo de vida\n'
"$PLATFORM" retire_legacy_theme
"$PLATFORM" shell_lifecycle migrate

printf '==> Generación unificada schema 2\n'
"$PLATFORM" system promote --repo "$REPO" --helpers "$helpers_generation"
printf '==> Verificación de la generación completa\n'
"$helpers_generation/cortetsu" verify
"$PLATFORM" install-transaction commit
transaction_active=0
unset CORTETSU_INSTALL_TRANSACTION

# Services and additive legacy state migration run only after the filesystem
# transaction is durable. They never restart the desktop shell implicitly.
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
    "$REPO/scripts/migrate-cortetsu-v2.sh" || printf 'WARN: migración legacy pendiente; vuelve a ejecutar scripts/migrate-cortetsu-v2.sh\n' >&2
else
    printf 'Migración legacy: no hay estado anterior; se omite.\n'
fi

# The pre-Cortetsu nvibrant.service runs a bare `nvibrant 128` at login and
# would overwrite the profile that cortetsu-nvibrant reapplies from Hyprland.
if systemctl --user is-enabled --quiet nvibrant.service 2>/dev/null; then
    systemctl --user disable nvibrant.service >/dev/null 2>&1 || true
    printf 'nvibrant.service desactivada; Cortetsu reaplica la vibrance. Revertir: systemctl --user enable nvibrant.service\n'
fi

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
# restart adopts the newly promoted executable even when the old unit was
# already active; enable --now alone would keep a legacy interpreter running.
if systemctl --user enable "$WALLPAPER_COLOR_UNIT" >/dev/null 2>&1 \
        && systemctl --user restart "$WALLPAPER_COLOR_UNIT" >/dev/null 2>&1; then
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

# Preserve the opt-in state of the power policy daemon while replacing an
# already running legacy executable with the current native generation.
if systemctl --user is-enabled --quiet cortetsu-power-auto.service 2>/dev/null \
        && systemctl --user is-active --quiet cortetsu-power-auto.service 2>/dev/null; then
    systemctl --user try-restart cortetsu-power-auto.service >/dev/null 2>&1 \
        || printf 'WARN: native power daemon restart is pending\n' >&2
fi

# A running Pomodoro daemon re-executes itself into the promoted helpers when
# woken; wake it now instead of waiting for the next Pomodoro command.
"$helpers_generation/cortetsu-pomodoro" wake >/dev/null 2>&1 || true

# Installation never deletes generations. The report below is computed after
# promotion, so it names exactly what an explicit `cortetsu gc --apply` would
# remove now; the user decides whether to run it.
printf '==> Generaciones (solo inspección, no se borra nada)\n'
"$helpers_generation/cortetsu" gc --keep 5 | grep -E '^(TOTAL_DELETE|TOTAL_RECLAIM|PLAN_ID|  DELETE)' || true
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
printf 'Shell personal: Fish es dependencia del perfil personal y se importa de forma explícita con cortetsu-platform import_fish.\n'
printf 'cortetsu-shell.service no se habilita implícitamente; una adopción existente sí se conserva.\n'
printf 'Rollback completo: cortetsu rollback\n'
printf 'Supervisión: cortetsu shell status\n'
