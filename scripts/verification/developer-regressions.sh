#!/usr/bin/env bash
# All historical source contracts run only in a disposable baseline checkout.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "$ROOT/scripts/verification/run-legacy-oracle.py" --suite
