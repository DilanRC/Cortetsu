#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE="$ROOT/cortetsu/ConnectivityWifiFixture.qml"
output="$(timeout 10s qs -p "$FIXTURE" --no-color 2>&1)" || {
    status=$?
    printf '%s\n' "$output" >&2
    printf 'Wi-Fi observation fixture failed (exit %s)\n' "$status" >&2
    exit "$status"
}

if ! grep -Fq 'WIFI_OBSERVED_PASS' <<<"$output"; then
    printf 'Wi-Fi observation fixture did not report success:\n%s\n' "$output" >&2
    exit 1
fi

if grep -Fq 'Unable to assign [undefined]' <<<"$output"; then
    printf 'Wi-Fi observation emitted undefined QML assignments:\n%s\n' "$output" >&2
    exit 1
fi

if grep -Fq 'Binding loop' <<<"$output"; then
    printf 'Wi-Fi observation emitted a binding loop:\n%s\n' "$output" >&2
    exit 1
fi

printf 'PASS: Wi-Fi observation handles a missing target without QML type warnings\n'
