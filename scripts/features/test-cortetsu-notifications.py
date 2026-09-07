import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
service = (modules / "CortetsuNotifications.qml").read_text(encoding="utf-8")
hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")
notifs = (repo / "cortetsu/services/Notifs.qml").read_text(encoding="utf-8")
notif_data = (repo / "cortetsu/services/NotifData.qml").read_text(encoding="utf-8")
view = (modules / "notifications/Notification.qml").read_text(encoding="utf-8")
wrapper = (modules / "notifications/Wrapper.qml").read_text(encoding="utf-8")

for marker in ("notifs.json", "notification-status.json", "property int count", "property bool dnd", "watchChanges: true"):
    assert marker in service, marker
assert "import qs.services" not in hub
assert "CortetsuNotifications.count" in hub and "CortetsuNotifications.dnd" in hub
assert not re.search(r"(?<!Cortetsu)Notifs\.", hub)
assert "notification-status.json" in notifs and "property bool dnd" in notifs
assert "NotificationServer" in notifs and "modelData.close()" in view
assert "function inspect(): string" in notifs
assert "import Quickshell.Io" in notifs
assert "model: Notifs.popups" in wrapper
assert "visibleNotifications" not in wrapper
for text in (notifs, notif_data, view):
    assert "Caelestia" not in text and "GlobalConfig" not in text
print("PASS: Bottom Hub notification state is Cortetsu-owned and XDG-backed")
