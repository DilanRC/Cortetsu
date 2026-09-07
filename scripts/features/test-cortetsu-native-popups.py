#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
popouts = ROOT / "cortetsu/modules/bar/popouts"
content = (ROOT / "cortetsu/base/modules/bar/popouts/Content.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
wrapper = (ROOT / "cortetsu/modules/bar/popouts/Wrapper.qml").read_text(encoding="utf-8")
content_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
interactions = (ROOT / "cortetsu/modules/drawers/Interactions.qml").read_text(encoding="utf-8")
status_segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")

for name, service in (
    ("CortetsuNetworkPopup.qml", "CortetsuNetwork"),
    ("CortetsuAudioPopup.qml", "CortetsuAudio"),
    ("CortetsuBluetoothPopup.qml", "Bluetooth"),
):
    text = (popouts / name).read_text(encoding="utf-8")
    assert "CortetsuPopupSurface" in text and "CortetsuListRow" in text
    assert "CortetsuDesign" in text and service in text
    assert "No devices nearby" in text or "No networks available" in text or "No device" in text

password = (popouts / "CortetsuWifiPasswordPopup.qml").read_text(encoding="utf-8")
for token in ("TextField", "Keys.onEscapePressed", "NetworkConnection.connectWithPassword", "8000", "errorText"):
    assert token in password, token

assert "sourceComponent: CortetsuNetworkPopup" in content
assert "sourceComponent: CortetsuAudioPopup" in content
assert "sourceComponent: CortetsuBluetoothPopup" in content
assert "sourceComponent: CortetsuWifiPasswordPopup" in content
network = (popouts / "CortetsuNetworkPopup.qml").read_text(encoding="utf-8")
assert "activeEthernet" in network and ': "lan"' in network
assert 'qsTr("Ethernet")' in network and 'qsTr("Connected")' in network
assert "Network unavailable" in network
assert "function closeAllPopouts(): void" in hub
assert "closeAllPopouts();" in hub
assert "id: hideTimer" in hub and "interval: 500" in hub
assert "hideTimer.restart();" in hub
assert "root.forceActiveFocus();" in wrapper
assert "value: WlrKeyboardFocus.Exclusive" in wrapper
assert 'onClicked: root.attachedControlRequested("network", root.centerFor(networkButton))' in status_segment
assert 'onClicked: root.attachedControlRequested("bluetooth", root.centerFor(bluetoothButton))' in status_segment
assert 'onClicked: root.detachedControlRequested("network")' not in status_segment
assert 'onClicked: root.detachedControlRequested("bluetooth")' not in status_segment
assert "sourceComponent: CortetsuDetachedPopup" in wrapper
assert "sourceComponent: Rectangle" not in wrapper
assert "Nexus" not in wrapper
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
assert "CortetsuWindowInfoPopup" in panels
popup_surface = (ROOT / "cortetsu/components/CortetsuPopupSurface.qml").read_text(encoding="utf-8")
assert "colorSurfaceGlassStrong" in popup_surface
assert "radiusLarge" in popup_surface
window_info = (popouts / "CortetsuWindowInfoPopup.qml").read_text(encoding="utf-8")
assert "CortetsuSurface" in window_info and "CortetsuButton" in window_info
assert "CortetsuTokens" not in window_info and "CortetsuColours" not in window_info
clip_wrapper = (ROOT / "cortetsu/modules/bar/popouts/ClipWrapper.qml").read_text(encoding="utf-8")
assert "content.bottomAttached || content.closing" in clip_wrapper
assert "anchors.leftMargin: (-implicitWidth - 5)" not in clip_wrapper
assert "ClipWrapper owns the screen-space placement" in clip_wrapper
assert "        x: 0\n        transformOrigin: Item.Bottom" in clip_wrapper
assert "transformOrigin: Item.Bottom" in clip_wrapper

# Native shell icons must stay on the GUI thread. Async image decoding in
# these always-created surfaces triggers Qt's cross-thread pixmap warning.
for path in (
    ROOT / "cortetsu/modules/HubButton.qml",
    ROOT / "cortetsu/modules/CortetsuAppRail.qml",
    ROOT / "cortetsu/modules/CortetsuTraySegment.qml",
    ROOT / "cortetsu/base/components/images/FadeImage.qml",
    ROOT / "cortetsu/base/components/images/CachingImage.qml",
    ROOT / "cortetsu/base/components/images/CachingIconImage.qml",
):
    assert "asynchronous: true" not in path.read_text(encoding="utf-8"), path

assert "closeTimer" in wrapper
assert "BarPopouts.CortetsuWindowInfoPopup" in panels
assert 'visible: popoutsWrapper.content.detachedMode === "winfo"' in panels
assert "focusable: panels.popouts.hasCurrent || (screenState.cortetsuState?.requiresWindowKeyboardFocus && !screenState.launcher && !screenState.session)" in content_window
assert "!popouts.bottomAttached &&" in interactions
assert "visible: panel.width > 0 && panel.height > 0 && (panel.offsetScale ?? 0) < 1" in content_window
for token in ('function control(mode: string): bool', 'function detachedControl(mode: string): bool', 'componentsFor(screen)?.popouts', '"activewindow"', '"kblayout"', '"lockstatus"', '"winfo"'):
    assert token in hub, token
assert 'if (mode === "winfo")' in hub
assert "hubRoot.toggleDetachedControlFor(screen, mode);" in hub
for name in ("CortetsuBatteryPopup.qml", "CortetsuActiveWindowPopup.qml", "CortetsuKeyboardPopup.qml", "CortetsuLockStatusPopup.qml", "CortetsuTrayMenu.qml"):
    owned = (popouts / name).read_text(encoding="utf-8")
    assert "CortetsuSurface" in owned or "CortetsuListRow" in owned or "CortetsuButton" in owned
    assert "CortetsuDesign" in owned
    assert "import qs.services" not in owned
    assert "import qs.components" not in owned
lock_status = (popouts / "CortetsuLockStatusPopup.qml").read_text(encoding="utf-8")
assert 'import "../../../services"' in lock_status
assert "Hypr.capsLock" in lock_status and "Hypr.numLock" in lock_status
tray_menu = (popouts / "CortetsuTrayMenu.qml").read_text(encoding="utf-8")
assert "CortetsuPopupSurface" in tray_menu
assert "id: stack" in tray_menu
assert "activeFocusOnTab" in tray_menu
assert "Keys.onPressed" in tray_menu
assert "Qt.Key_Right" in tray_menu and "Qt.Key_Left" in tray_menu
assert "Qt.Key_Escape" in tray_menu
assert "focused: activeFocus" in tray_menu
for legacy in ("sourceComponent: Battery", "sourceComponent: ActiveWindow", "sourceComponent: KbLayout", "sourceComponent: LockStatus", "sourceComponent: TrayMenu"):
    assert legacy not in content, legacy
assert "sourceComponent: Network {" not in content
assert "sourceComponent: AudioPopout {" not in content
assert "sourceComponent: Bluetooth {" not in content
print("PASS: Wi-Fi, audio and Bluetooth popouts are first-party views over owned services")
