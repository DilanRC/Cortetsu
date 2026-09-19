from pathlib import Path

path = Path(__file__).resolve().parents[2] / "cortetsu/modules/notifications/Wrapper.qml"
source = path.read_text(encoding="utf-8")
for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
    assert legacy not in source, legacy
assert "Notifs.popups()" in source
assert "Notification {" in source
assert "required property var screenState" in source
print("PASS: notification popup host is first-party")
