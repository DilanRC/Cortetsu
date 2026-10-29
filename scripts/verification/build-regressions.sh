#!/usr/bin/env bash
# Current native runtime UI checks. Historical interpreter tests live in the
# explicitly separate developer-regressions.sh frozen-oracle runner.
set -euo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
STAGING="${1:?usage: build-regressions.sh STAGED_RUNTIME}"
python3 "$REPO/scripts/verification/test-native-source.py"
python3 "$REPO/cortetsu/tests/test-startup-inventory.py"
for suite in hardware hypr surfaces calendar pomodoro policy polkit prompt; do
    QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input "$REPO/cortetsu/tests/qml/$suite"
done
python3 "$REPO/scripts/features/test-native-bottom-hub.py" --runtime "$STAGING/modules/BottomHub.qml"
python3 "$REPO/scripts/features/test-cortetsu-hub-controls-runtime.py"
# Redesigned surfaces stay at zero design-lint findings (phase 3).
python3 "$REPO/scripts/verification/qml-design-lint.py" --strict \
    "$REPO/cortetsu/modules/BottomHub.qml" "$REPO/cortetsu/modules/CortetsuBottomHubView.qml" \
    "$REPO/cortetsu/modules/HubButton.qml" "$REPO/cortetsu/modules/StatusPill.qml" \
    "$REPO/cortetsu/modules/CortetsuWorkspaceDots.qml" "$REPO/cortetsu/modules/CortetsuAppRail.qml" \
    "$REPO/cortetsu/modules/CortetsuStatusSegment.qml" "$REPO/cortetsu/modules/bar" \
    "$REPO/cortetsu/base/modules/bar/popouts/kblayout" "$REPO/cortetsu/components/CortetsuIconBadge.qml"
python3 "$REPO/scripts/features/test-cortetsu-surface-registry.py"
python3 "$REPO/scripts/features/test-hypr-actions.py"
python3 "$REPO/scripts/features/test-hypr-event-policy.py"
python3 "$REPO/scripts/features/test-qml-design-lint.py"
python3 "$REPO/scripts/verification/qml-design-lint.py" --summary
python3 "$REPO/scripts/features/test-cortetsu-quality.py"
python3 "$REPO/scripts/features/test-cortetsu-settings.py"
python3 "$REPO/scripts/features/test-cortetsu-v2-bridge.py"
node "$REPO/scripts/features/test-cortetsu-policy-model.mjs"
node "$REPO/scripts/features/test-notification-reconcile.mjs"
python3 "$REPO/scripts/features/test-cortetsu-v2-bridge-runtime.py"
python3 "$REPO/scripts/features/test-notification-history-runtime.py"
