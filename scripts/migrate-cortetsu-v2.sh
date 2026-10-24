#!/usr/bin/env bash
set -euo pipefail

DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DATA_ROOT/migrations/$STAMP"
MARKER="$DATA_ROOT/.v2-migrated"
WARNINGS="$BACKUP/COPY_WARNINGS.log"

[[ ! -e "$MARKER" ]] || exit 0
mkdir -p "$BACKUP" "$CONFIG_HOME/cortetsu" "$STATE_HOME/cortetsu" "$CACHE_HOME/cortetsu"

record_copy_warning() {
    local operation="$1"
    local source="$2"
    local destination="$3"
    local error_file="$4"

    {
        printf '[%s] %s\n' "$(date --iso-8601=seconds)" "$operation"
        printf 'source=%s\n' "$source"
        printf 'destination=%s\n' "$destination"
        if [[ -s "$error_file" ]]; then
            sed 's/^/  /' "$error_file"
        fi
        printf '\n'
    } >> "$WARNINGS"

    printf 'WARN: copia parcial de %s; se conservará todo lo legible. Detalles: %s\n' "$source" "$WARNINGS" >&2
}

backup_path() {
    local source="$1"
    local label="$2"
    local destination error_file

    if [[ -e "$source" || -L "$source" ]]; then
        destination="$BACKUP/$label"
        error_file="$BACKUP/.copy-error.$$"
        mkdir -p "$(dirname "$destination")"
        if ! cp -a "$source" "$destination" 2>"$error_file"; then
            record_copy_warning "backup" "$source" "$destination" "$error_file"
        fi
        rm -f "$error_file"
    fi
}

copy_tree_if_missing() {
    local source="$1"
    local destination="$2"
    local error_file

    if [[ -d "$source" ]]; then
        error_file="$BACKUP/.copy-error.$$"
        mkdir -p "$destination"
        if ! cp -an "$source/." "$destination/" 2>"$error_file"; then
            record_copy_warning "merge" "$source" "$destination" "$error_file"
        fi
        rm -f "$error_file"
    fi
}

copy_if_missing() {
    local source="$1"
    local destination="$2"
    local mode="${3:-}"
    if [[ -f "$source" && ! -e "$destination" ]]; then
        mkdir -p "$(dirname "$destination")"
        cp -a "$source" "$destination"
        [[ -z "$mode" ]] || chmod "$mode" "$destination"
    fi
}

# Best-effort archival: legacy trees may contain historical root-owned artifacts.
# Those must never prevent the canonical Cortetsu runtime from being built.
backup_path "$CONFIG_HOME/caerice" "config/caerice"
backup_path "$STATE_HOME/caerice" "state/caerice"
backup_path "$CONFIG_HOME/quickshell/caelestia" "runtime/quickshell-caelestia"

# Required user state is migrated strictly. Failure here is meaningful and should
# stop the migration rather than silently losing active Calendar/Pomodoro state.
copy_if_missing "$CONFIG_HOME/caelestia/calendar-client.json" "$CONFIG_HOME/cortetsu/calendar-client.json" 600
copy_if_missing "$CONFIG_HOME/caelestia/calendar-selection.json" "$CONFIG_HOME/cortetsu/calendar-selection.json" 600
copy_if_missing "$CACHE_HOME/caelestia/calendar-events.json" "$CACHE_HOME/cortetsu/calendar-events.json" 600
copy_if_missing "$STATE_HOME/caelestia/pomodoro.json" "$STATE_HOME/cortetsu/pomodoro.json" 600

# Merge any additional legacy CaeRice-owned state without overwriting canonical
# Cortetsu files. Unreadable historical artifacts are logged and skipped.
copy_tree_if_missing "$CONFIG_HOME/caerice" "$CONFIG_HOME/cortetsu"
copy_tree_if_missing "$STATE_HOME/caerice" "$STATE_HOME/cortetsu"

# Migrate the Calendar refresh token without ever printing it. The old secret is
# only cleared after the canonical entry is confirmed stored.
if command -v secret-tool >/dev/null 2>&1; then
    canonical_secret="$(secret-tool lookup service cortetsu-google-calendar 2>/dev/null || true)"
    if [[ -z "$canonical_secret" ]]; then
        legacy_secret="$(secret-tool lookup service caerice-google-calendar 2>/dev/null || true)"
        if [[ -n "$legacy_secret" ]]; then
            if printf '%s' "$legacy_secret" | secret-tool store --label='Cortetsu Google Calendar refresh token' service cortetsu-google-calendar >/dev/null 2>&1; then
                secret-tool clear service caerice-google-calendar >/dev/null 2>&1 || true
            fi
        fi
        unset legacy_secret
    fi
    unset canonical_secret
fi

mkdir -p "$BACKUP/bin"
shopt -s nullglob
for old in "$HOME"/.local/bin/caerice-*; do
    cp -a "$old" "$BACKUP/bin/$(basename "$old")"
    rm -f "$old"
done
shopt -u nullglob

OLD_UNIT="caerice-power-auto.service"
if systemctl --user is-enabled "$OLD_UNIT" >/dev/null 2>&1; then
    printf 'enabled\n' > "$DATA_ROOT/.power-auto-was-enabled"
fi
systemctl --user disable "$OLD_UNIT" >/dev/null 2>&1 || true
if systemctl --user is-active --quiet "$OLD_UNIT"; then
    printf 'Legacy power automation remains active. To switch explicitly: systemctl --user stop %s && systemctl --user start cortetsu-power-auto.service\n' "$OLD_UNIT"
fi
if [[ -f "$CONFIG_HOME/systemd/user/$OLD_UNIT" ]]; then
    backup_path "$CONFIG_HOME/systemd/user/$OLD_UNIT" "systemd/$OLD_UNIT"
    rm -f "$CONFIG_HOME/systemd/user/$OLD_UNIT"
fi
systemctl --user daemon-reload >/dev/null 2>&1 || true

printf '%s\n' "$STAMP" > "$MARKER"
printf 'Cortetsu v2 migration backup: %s\n' "$BACKUP"
if [[ -s "$WARNINGS" ]]; then
    printf 'Cortetsu v2 migration warnings: %s\n' "$WARNINGS" >&2
fi
