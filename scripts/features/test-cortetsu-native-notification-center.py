#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
inventory = (ROOT / "docs/architecture/qml-surface-inventory.md").read_text(encoding="utf-8")
assert "| Notifications | `modules/sidebar/Content.qml`, `modules/notifications/Wrapper.qml`, `Notification.qml` |" in inventory
content = (ROOT / "cortetsu/modules/sidebar/Content.qml").read_text(encoding="utf-8")
notification = (ROOT / "cortetsu/modules/notifications/Notification.qml").read_text(encoding="utf-8")
notif_data = (ROOT / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
for token in (
    "CortetsuNotifications.history",
    "CortetsuNotifications.dnd",
    "CortetsuNotifications.clear()",
    "Notifs.clear()",
    'title: qsTr(\"Now\")',
    'title: qsTr(\"History\")',
    'title: qsTr(\"All clear\")',
    'title: qsTr(\"No saved notifications\")',
    "CortetsuStateMessage",
    "CortetsuToggle",
    "CortetsuButton",
    "CortetsuListRow",
):
    assert token in content, token
assert "GlobalConfig" not in content and "Caelestia" not in content
assert "id: contentLayout" in notification
assert "contentLayout.implicitHeight" in notification
assert 'import "../CortetsuDesign.js" as CortetsuDesign' in notification
assert 'import "../CortetsuTypography.js" as CortetsuTypography' in notification
assert "modelData.appName" in notification
assert "modelData.image" in notification
assert "modelData.urgency >= 2" in notification
assert "root.modelData.actions.length > 0 || root.hovered || root.expanded || root.activeFocus" in notification
assert 'label: qsTr("Dismiss")' in notification
assert "dismissalRequested" in notif_data
assert "function dismissAndRemove" in notif_data
assert "if (closed)" in notif_data
wrapper = (ROOT / "cortetsu/modules/notifications/Wrapper.qml").read_text(encoding="utf-8")
assert "modelData: root.visibleNotifications[index]" in wrapper
assert "modelData: root.active[index]" in content
assert "required property var modelData" in notification
assert "modelData.timeStr" in content
print("PASS: notification center owns live, history, DND, clear and empty states")
