#!/usr/bin/env bash
# Feature contracts that drift silently when nothing runs them: the shell
# unit and Hyprland lifecycle migration, the soft reload result, and the
# saturation write queue.
# Python is only the test driver here; the runtime and the CLI stay
# interpreter-free (scripts/verification/test-native-source.py).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for test in test-shell-lifecycle.py test-shell-reload-result.py test-display-vibrance-service.py; do
    python3 "$ROOT/scripts/features/$test"
done
