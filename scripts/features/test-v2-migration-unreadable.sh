#!/usr/bin/env bash
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TMP="$(mktemp -d -t cortetsu-migration-test-XXXXXX)"
trap 'chmod -R u+rwX "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

HOME_DIR="$TMP/home"
CONFIG_HOME="$HOME_DIR/.config"
STATE_HOME="$HOME_DIR/.local/state"
CACHE_HOME="$HOME_DIR/.cache"
DATA_HOME="$HOME_DIR/.local/share"
FAKE_BIN="$TMP/bin"

mkdir -p \
    "$STATE_HOME/caerice/backups/wallpaper-manager-broken/files" \
    "$STATE_HOME/caelestia" \
    "$CONFIG_HOME/caelestia" \
    "$CACHE_HOME" \
    "$DATA_HOME" \
    "$FAKE_BIN"

printf 'readable legacy state\n' > "$STATE_HOME/caerice/keep.txt"
printf 'historical artifact\n' > "$STATE_HOME/caerice/backups/wallpaper-manager-broken/files/4"
chmod 000 "$STATE_HOME/caerice/backups/wallpaper-manager-broken/files/4"
printf '{"phase":"IDLE"}\n' > "$STATE_HOME/caelestia/pomodoro.json"

cat > "$FAKE_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/systemctl"

cat > "$FAKE_BIN/secret-tool" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/secret-tool"

run_migration() {
    env \
        HOME="$HOME_DIR" \
        XDG_CONFIG_HOME="$CONFIG_HOME" \
        XDG_STATE_HOME="$STATE_HOME" \
        XDG_CACHE_HOME="$CACHE_HOME" \
        XDG_DATA_HOME="$DATA_HOME" \
        CORTETSU_DATA_ROOT="$DATA_HOME/cortetsu" \
        PATH="$FAKE_BIN:/usr/bin:/bin" \
        bash "$REPO/scripts/migrate-cortetsu-v2.sh"
}

run_migration

test -f "$DATA_HOME/cortetsu/.v2-migrated"
test -f "$STATE_HOME/cortetsu/pomodoro.json"
test -f "$STATE_HOME/cortetsu/keep.txt"

warnings="$(find "$DATA_HOME/cortetsu/migrations" -type f -name COPY_WARNINGS.log -print -quit)"
test -n "$warnings"
grep -q 'state/caerice' "$warnings"
grep -q 'wallpaper-manager-broken/files/4' "$warnings"

migration_count_before="$(find "$DATA_HOME/cortetsu/migrations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
run_migration
migration_count_after="$(find "$DATA_HOME/cortetsu/migrations" -mindepth 1 -maxdepth 1 -type d | wc -l)"
test "$migration_count_before" -eq "$migration_count_after"

printf 'PASS: unreadable legacy artifacts are warned, readable state migrates, and v2 migration remains idempotent\n'
