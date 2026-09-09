#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/sidebar/Content.qml").read_text(encoding="utf-8")
notification = (ROOT / "cortetsu/modules/notifications/Notification.qml").read_text(encoding="utf-8")
notif_data = (ROOT / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
sections = sum(source.count(f'title: qsTr(\"{name}\")') for name in ("Now", "History"))
states = sum(source.count(token) for token in ("All clear", "No saved notifications", "Do not disturb"))
assert sections == 2
assert states >= 2
assert source.count("CortetsuDesign.") >= 6
assert "contentLayout.implicitHeight" in notification
assert "readonly property bool hasModelData" in notification
assert "readonly property bool closed: !hasModelData || modelData.closed" in notification
assert "Component.onDestruction: if (root.hasModelData)" in notification
assert 'import "../CortetsuDesign.js" as CortetsuDesign' in notification
assert 'import "../CortetsuTypography.js" as CortetsuTypography' in notification
assert "modelData.appName" in notification and "modelData.image" in notification
assert "readonly property bool urgent: urgency >= 2" in notification
assert "Qt.alpha(CortetsuDesign.colorPrimary, 0.12)" in notification
assert ": CortetsuDesign.colorPrimary" in notification
assert "Qt.alpha(CortetsuDesign.colorTertiary, 0.12)" not in notification
assert "root.notificationActions.length > 0 || root.hovered || root.expanded || root.activeFocus" in notification
assert 'label: qsTr("Dismiss")' in notification
assert "dismissalRequested" in notif_data
assert "function dismissAndRemove" in notif_data
print("PASS: notification center eval covers hierarchy, empty states and visual token use")
