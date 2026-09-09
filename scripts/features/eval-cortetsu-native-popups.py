#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
popouts = ROOT / "cortetsu/modules/bar/popouts"
required = ("CortetsuNetworkPopup.qml", "CortetsuAudioPopup.qml", "CortetsuBluetoothPopup.qml")
for name in required:
    text = (popouts / name).read_text(encoding="utf-8")
    for token in ("CortetsuPopupSurface", "CortetsuSectionHeader", "CortetsuListRow"):
        assert token in text, f"{name} lacks {token}"
network = (popouts / "CortetsuNetworkPopup.qml").read_text(encoding="utf-8")
assert "activeEthernet" in network
assert "wiredActive" in network
assert ': "lan"' in network
popup_surface = (ROOT / "cortetsu/components/CortetsuPopupSurface.qml").read_text(encoding="utf-8")
assert "CortetsuSurface" in popup_surface
assert "CortetsuDesign.radiusLarge" in popup_surface
detached = (popouts / "CortetsuDetachedPopup.qml").read_text(encoding="utf-8")
assert "\nItem {" in detached
assert "CortetsuSurface {" not in detached
assert "radiusValue:" not in detached and "baseColor:" not in detached and "outlined:" not in detached
assert "MouseArea" in detached and "z: -1" in detached
assert (ROOT / "cortetsu/base/modules/bar/popouts/Content.qml").is_file()
password = (popouts / "CortetsuWifiPasswordPopup.qml").read_text(encoding="utf-8")
assert password.count("CortetsuButton") >= 2
assert "NetworkConnection.connectWithPassword" in password
tray = (popouts / "CortetsuTrayMenu.qml").read_text(encoding="utf-8")
assert all(token in tray for token in ("activeFocusOnTab", "Qt.Key_Right", "Qt.Key_Left", "Qt.Key_Escape", "focused: activeFocus"))
assert "CortetsuPopupSurface" in tray
content_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
assert "focusable: panels.popouts.hasCurrent || (screenState.cortetsuState?.requiresWindowKeyboardFocus && !screenState.launcher && !screenState.session)" in content_window
print("PASS: native popup eval covers network, audio and Bluetooth hierarchy and states")
