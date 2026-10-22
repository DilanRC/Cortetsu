#!/usr/bin/env bash
# Rollback includes shell, dotfiles and the matching helper generation.
set -euo pipefail
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
BUNDLE="$(dirname "$SELF")"
if [[ -x "$BUNDLE/cortetsu-platform" ]]; then
    exec "$BUNDLE/cortetsu-platform" system rollback "$@"
fi
REPO="$(cd "$BUNDLE/../.." && pwd)"
if [[ -x "$REPO/dist/native/cortetsu-platform" ]]; then
    exec "$REPO/dist/native/cortetsu-platform" system rollback "$@"
fi
printf 'ERROR: falta el owner nativo de generaciones; ejecuta scripts/build-native.sh\n' >&2
exit 1
