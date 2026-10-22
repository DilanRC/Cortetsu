from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
service = (modules / "CortetsuNotifications.qml").read_text(encoding="utf-8")
bin_dir = repo / "cortetsu/bin"
helper = (bin_dir / "cortetsu-notifications").read_text(encoding="utf-8")

# Controller exposes history/dismiss/clear/DND actions with no GlobalConfig coupling,
# and routes every mutation through the deterministic helper binary (never edits
# JSON inline in QML).
for marker in (
    "property var history: []",
    'function dismiss(id: var): void {\n        Quickshell.execDetached(["cortetsu-notifications", "dismiss", String(id)]);',
    'function clear(): void {\n        Quickshell.execDetached(["cortetsu-notifications", "clear"]);',
    'function toggleDnd(): void {\n        Quickshell.execDetached(["cortetsu-notifications", "dnd", "toggle"]);',
    'target: "cortetsu-notifications"',
    "function isDndEnabled(): bool { return root.dnd; }",
):
    assert marker in service, marker
assert "GlobalConfig." not in service
assert "Caelestia." not in service
assert "import qs." not in service

# The stable entry point selects its generation's Rust owner; Python remains
# only in the archived development oracle used by parity tests.
assert helper.startswith("#!/usr/bin/env bash")
assert 'exec "$BUNDLE/cortetsu-notifications-rs" "$@"' in helper
assert "python" not in helper.lower()
owner = (repo / "cortetsu/notification-helper/src/lib.rs").read_text(encoding="utf-8")
for marker in ('"dismiss"', '"clear"', '"dnd"', "notifs.json", "notification-status.json"):
    assert marker in owner, marker
assert "GlobalConfig." not in helper and "Caelestia." not in helper
notifs = (repo / "cortetsu/services/Notifs.qml").read_text(encoding="utf-8")
assert '["cortetsu-notifications", "merge"]' in notifs
assert '["cortetsu-notifications", "dnd", "ensure"]' in notifs
for source in (notifs, service):
    assert "CortetsuNotificationModel.js" in source
    assert "notifs-clear.json" in source
    assert ".setText(" not in source, "QML must not bypass the native state owner"

print("PASS: notification history/DND mutations use the native owner and shared readback contract")
