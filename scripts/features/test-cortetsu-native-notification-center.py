#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
inventory = (ROOT / "docs/architecture/qml-surface-inventory.md").read_text(encoding="utf-8")
assert "| Notifications | `modules/sidebar/Content.qml`, `modules/notifications/Wrapper.qml`, `Notification.qml` |" in inventory
content = (ROOT / "cortetsu/modules/sidebar/Content.qml").read_text(encoding="utf-8")
notification = (ROOT / "cortetsu/modules/notifications/Notification.qml").read_text(encoding="utf-8")
notif_data = (ROOT / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
service = (ROOT / "cortetsu/services/Notifs.qml").read_text(encoding="utf-8")
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
assert "readonly property bool hasModelData" in notification
assert "readonly property bool closed: !hasModelData || modelData.closed" in notification
assert "Component.onDestruction: if (root.hasModelData)" in notification
assert 'import "../CortetsuDesign.js" as CortetsuDesign' in notification
assert 'import "../CortetsuTypography.js" as CortetsuTypography' in notification
assert "modelData.appName" in notification
assert "modelData.image" in notification
assert "readonly property bool urgent: urgency >= 2" in notification
assert "Qt.alpha(CortetsuDesign.colorPrimary, 0.12)" in notification
assert ": CortetsuDesign.colorPrimary" in notification
assert "Qt.alpha(CortetsuDesign.colorTertiary, 0.12)" not in notification
assert "root.notificationActions.length > 0 || root.hovered || root.expanded || root.activeFocus" in notification
assert 'label: qsTr("Dismiss")' in notification
assert "dismissalRequested" in notif_data
assert "function dismissAndRemove" in notif_data
assert "if (closed)" in notif_data
assert "property var list: []" in service
assert "property list<NotifData> list" not in service
assert "property int revision: 0" in service
assert "function notClosed(): var" in service
assert "function popups(): var" in service
assert "root.revision;" in service
wrapper = (ROOT / "cortetsu/modules/notifications/Wrapper.qml").read_text(encoding="utf-8")
assert "model: Notifs.popups()" in wrapper
assert "visibleNotifications" not in wrapper
assert "modelData: root.active[index]" in content
assert "required property var modelData" in notification
assert "focus: false" in notification
assert "focus: index === 0" in content
assert "modelData.timeStr" in content
print("PASS: notification center owns live, history, DND, clear and empty states")
