#!/usr/bin/env bash
# Build one complete, generation-ready native runtime. Never installs it.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT="${CORTETSU_NATIVE_OUTPUT:-$REPO/dist/native}"
[[ "$OUTPUT" == /* && "$OUTPUT" != / ]] || { echo 'ERROR: native output must be absolute' >&2; exit 2; }
mkdir -p "$(dirname "$OUTPUT")"
STAGING="$(mktemp -d "$(dirname "$OUTPUT")/.native-XXXXXXXX")"
trap 'rm -rf -- "$STAGING"' EXIT
for record in \
    'keyboards cortetsu-keybinds' \
    'notification-helper cortetsu-notifications-rs' \
    'display-presets-rs cortetsu-display-presets-rs' \
    'prune-applications-rs cortetsu-prune-applications-rs' \
    'rescue cortetsu-rescue' \
    'platform-rs cortetsu-platform' \
    'hardware-runtime-rs cortetsu-hardware-runtime' \
    'desktop-runtime-rs cortetsu-desktop-runtime'; do
    read -r crate binary <<< "$record"
    printf 'Building %s\n' "$binary"
    cargo build --release --locked --manifest-path "$REPO/cortetsu/$crate/Cargo.toml"
    target="${CARGO_TARGET_DIR:-$REPO/cortetsu/$crate/target}"
    install -m 0755 "$target/release/$binary" "$STAGING/$binary"
done
for binary in cortetsu-coordinator cortetsu-bridge cortetsu-shadow cortetsu-policy cortetsu-python-inventory; do
    (cd "$REPO/cortetsu/protocol" && CGO_ENABLED=0 go build -trimpath -ldflags='-s -w' -o "$STAGING/$binary" "./cmd/$binary")
done

# Shell-only helpers preserve their existing CLI. Python oracles are never copied.
while IFS= read -r -d '' source; do
    IFS= read -r first < "$source" || true
    if [[ "$first" == '#!'* && "$first" != *python* ]]; then
        install -m 0755 "$source" "$STAGING/$(basename "$source")"
    fi
done < <(find "$REPO/cortetsu/bin" -maxdepth 1 -type f -name 'cortetsu-*' -print0 | sort -z)

while IFS=$'\t' read -r name binary command; do
    [[ -n "$name" && "$name" != \#* ]] || continue
    [[ "$name" =~ ^cortetsu-[a-z0-9-]+$ && "$binary" =~ ^cortetsu-[a-z0-9-]+$ ]] || exit 2
    [[ -x "$STAGING/$binary" ]] || { echo "ERROR: missing owner $binary" >&2; exit 1; }
    {
        cat <<'SH'
#!/usr/bin/env bash
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
BUNDLE="$(dirname "$SELF")"
DATA_ROOT="${CORTETSU_DATA_ROOT:-${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu}"
if [[ -z "${CORTETSU_REPO_ROOT:-}" && -L "$DATA_ROOT/repository" ]]; then
    export CORTETSU_REPO_ROOT="$(readlink -f "$DATA_ROOT/repository")"
fi
if [[ -z "${CORTETSU_RESOURCE_ROOT:-}" ]]; then
    if [[ -x "$BUNDLE/cortetsu-resource-root" ]]; then
        export CORTETSU_RESOURCE_ROOT="$("$BUNDLE/cortetsu-resource-root")"
    fi
fi
SH
        if [[ "$command" == - ]]; then
            printf 'exec "$BUNDLE/%s" "$@"\n' "$binary"
        else
            [[ "$command" =~ ^[a-z0-9_-]+$ ]] || exit 2
            printf 'exec "$BUNDLE/%s" %q "$@"\n' "$binary" "$command"
        fi
    } > "$STAGING/$name"
    chmod 0755 "$STAGING/$name"
done < "$REPO/cortetsu/native-helpers.tsv"
install -m 0755 "$REPO/scripts/cortetsu" "$STAGING/cortetsu"
install -m 0755 "$REPO/cortetsu/bin/rollback-runtime.sh" "$STAGING/cortetsu-rollback"
{
    printf '#!/usr/bin/env bash\nset -euo pipefail\n'
    printf 'printf '\''%%s\\n'\'' %q\n' "${CORTETSU_NATIVE_RESOURCE_ROOT:-$REPO/cortetsu}"
} > "$STAGING/cortetsu-resource-root"
chmod 0755 "$STAGING/cortetsu-resource-root"

for helper in "$STAGING"/*; do
    if [[ "$(head -c 2 "$helper")" == '#!' ]] && grep -Eq '^#!.*python|(^|[[:space:]])python3([[:space:]]|$)' "$helper"; then
        echo "ERROR: interpreter dependency in $(basename "$helper")" >&2; exit 1
    fi
done
# Keep the previous build available until all compilers and the runtime gate pass.
if [[ -e "$OUTPUT" ]]; then
    [[ -d "$OUTPUT" && ! -L "$OUTPUT" ]] || { echo 'ERROR: unsafe native output' >&2; exit 1; }
    OLD="${OUTPUT}.previous.$$"
    mv -- "$OUTPUT" "$OLD"
    if ! mv -- "$STAGING" "$OUTPUT"; then mv -- "$OLD" "$OUTPUT"; exit 1; fi
    rm -rf -- "$OLD"
else
    mv -- "$STAGING" "$OUTPUT"
fi
printf 'Native runtime: %s\n' "$OUTPUT"
