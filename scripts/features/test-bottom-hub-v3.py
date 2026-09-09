#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
MODULES = REPO / "cortetsu/modules"
BOTTOM_HUB = MODULES / "BottomHub.qml"
VIEW = MODULES / "CortetsuBottomHubView.qml"
MODE = MODULES / "CortetsuModeSegment.qml"
RAIL = MODULES / "CortetsuAppRail.qml"
TRAY = MODULES / "CortetsuTraySegment.qml"
STATUS = MODULES / "CortetsuStatusSegment.qml"
HUB_BUTTON = MODULES / "HubButton.qml"


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"FAIL: missing {label}")


def require_order(text: str, labels: list[tuple[str, str]]) -> None:
    cursor = -1
    for needle, label in labels:
        pos = text.find(needle)
        if pos < 0:
            raise SystemExit(f"FAIL: missing {label}")
        if pos <= cursor:
            raise SystemExit(f"FAIL: {label} is out of order")
        cursor = pos


def require_balanced_qml(text: str, path: Path) -> None:
    stack = []
    pairs = {"{": "}", "(": ")", "[": "]"}
    closing = set(pairs.values())
    quote: str | None = None
    escaped = False

    for line_no, line in enumerate(text.splitlines(), start=1):
        for char in line:
            if quote:
                if escaped:
                    escaped = False
                elif char == "\\":
                    escaped = True
                elif char == quote:
                    quote = None
                continue

            if char in ("'", '"', "`"):
                quote = char
            elif char in pairs:
                stack.append((char, line_no))
            elif char in closing:
                if not stack or pairs[stack[-1][0]] != char:
                    raise SystemExit(f"FAIL: unbalanced {char} in {path}:{line_no}")
                stack.pop()

    if stack:
        char, line_no = stack[-1]
        raise SystemExit(f"FAIL: unclosed {char} in {path}:{line_no}")


def main() -> None:
    bottom = BOTTOM_HUB.read_text(encoding="utf-8")
    view = VIEW.read_text(encoding="utf-8")
    mode = MODE.read_text(encoding="utf-8")
    rail = RAIL.read_text(encoding="utf-8")
    tray = TRAY.read_text(encoding="utf-8")
    status = STATUS.read_text(encoding="utf-8")
    button = HUB_BUTTON.read_text(encoding="utf-8")

    for path, text in (
        (BOTTOM_HUB, bottom),
        (VIEW, view),
        (MODE, mode),
        (RAIL, rail),
        (TRAY, tray),
        (STATUS, status),
        (HUB_BUTTON, button),
    ):
        require_balanced_qml(text, path)

    require(bottom, "readonly property bool panelActive:", "panel activity state")
    require(bottom, "readonly property int hubMargin: 8", "full-width hub margin")
    require(bottom, "implicitWidth: (modelData?.width ?? 0) - hubMargin * 2", "monitor-width bar")
    require(bottom, "CortetsuBottomHubView {", "first-party view boundary")
    if "StyledRect {" in bottom or "Colours." in bottom or "Tokens." in bottom:
        raise SystemExit("FAIL: controller must not contain legacy visual primitives")

    require(view, "readonly property real appRailMaxWidth:", "bounded app rail width")
    require(view, "id: leftSegment", "anchored left segment")
    require(view, "anchors.horizontalCenter: parent.horizontalCenter", "centered app segment")
    require(view, "id: traySegment", "tray segment")
    require(view, "id: statusSegment", "right status segment")
    require_order(
        view,
        [
            ("id: leftSegment", "left mode segment"),
            ("id: appSegment", "center app segment"),
            ("id: traySegment", "tray segment"),
            ("id: statusSegment", "right status segment"),
        ],
    )

    require(rail, "Flickable {", "scrollable app rail")
    require(rail, "interactive: contentWidth > width", "rail overflow interaction")
    require(rail, "visible: appItem.modelData.pinned && !appItem.modelData.running", "pinned dormant badge")
    require(rail, "model: Math.min(appItem.modelData.windowCount, 4)", "capped window indicators")
    require(rail, "root.togglePinnedRequested(appItem.modelData.key);", "right-click pin request")
    require(rail, "root.closeRequested(appItem.modelData.key);", "middle-click close request")
    require(rail, "root.cycleRequested(appItem.modelData.key, -1);", "wheel previous request")
    require(rail, "root.cycleRequested(appItem.modelData.key, 1);", "wheel next request")

    require(mode, 'imageSource: Quickshell.shellPath("assets/branding/cortetsu-mark.svg")', "Cortetsu launcher logo")
    if "/usr/share/icons/cachyos.svg" in mode:
        raise SystemExit("FAIL: BottomHub product identity must not fall back to the distro badge")
    require(mode, "CortetsuWorkspaceDots {", "workspace indicator component")

    require(bottom, "Icons.getVolumeIcon(CortetsuAudio.volume, CortetsuAudio.muted)", "volume icon controller")
    require(bottom, "Icons.getNetworkIcon(CortetsuNetwork.active.strength ?? 0)", "network icon controller")
    require(bottom, '"bluetooth_connected"', "bluetooth state icon")
    require(bottom, "Icons.getBatteryIcon(UPower.displayDevice.percentage, batteryCharging)", "battery icon controller")
    require(bottom, "SystemTray.items.values", "system tray controller")
    require(bottom, "item.icon || Icons.getTrayIcon(item.id, item.icon)", "tray icon priority")
    require(bottom, "`traymenu${sourceIndex}`", "native tray hover menu")
    require(tray, "Image {", "first-party tray image")
    if "ColouredIcon" in tray or "Config.bar.tray.recolour" in tray:
        raise SystemExit("FAIL: tray view must not depend on Caelestia recolour primitives")

    require(status, "id: systemControls", "system hover island")
    require(status, "required property bool audioVisible", "audio visibility contract")
    require(status, "required property bool networkVisible", "network visibility contract")
    require(status, "required property bool bluetoothVisible", "Bluetooth visibility contract")
    require(status, "required property bool batteryVisible", "battery visibility contract")
    require(status, "visible: root.audioVisible", "audio visibility binding")
    require(status, "visible: root.networkVisible", "network visibility binding")
    require(status, "visible: root.bluetoothVisible", "Bluetooth visibility binding")
    require(status, "visible: root.batteryVisible", "battery visibility binding")
    require(status, "HoverHandler {", "system hover island handler")
    require(status, "root.attachedControlExited();", "single island exit")
    require(status, 'root.attachedControlEntered("audio", root.centerFor(volumeButton))', "anchored audio hover")
    require(status, 'root.attachedControlEntered("network", root.centerFor(networkButton))', "anchored network hover")
    require(status, 'root.attachedControlEntered("bluetooth", root.centerFor(bluetoothButton))', "anchored bluetooth hover")
    require(status, 'root.attachedControlEntered("battery", root.centerFor(batteryButton))', "anchored battery hover")
    if status.count("root.attachedControlExited();") != 1:
        raise SystemExit("FAIL: attached system controls must close only when the hover island is exited")
    require(status, 'if (root.statusPopoutsEnabled)\n                    root.attachedControlRequested("network", root.centerFor(networkButton))', "guarded network click request")
    require(status, 'if (root.statusPopoutsEnabled)\n                    root.attachedControlRequested("bluetooth", root.centerFor(bluetoothButton))', "guarded bluetooth click request")
    require(status, 'if (root.statusPopoutsEnabled)\n                    root.attachedControlRequested("battery", root.centerFor(batteryButton))', "guarded battery click request")
    require(status, "tooltipOnHover: false", "rich popup tooltip suppression")
    require(status, "onClicked: root.calendarRequested()", "clock-click calendar request")

    require(bottom, "onLauncherRequested: hubRoot.toggleLauncherFor(win.modelData)", "launcher action")
    require(bottom, "onNotificationsRequested: hubRoot.toggleSidebarFor(win.modelData)", "sidebar action")
    require(bottom, "onAppTogglePinnedRequested: key => win.togglePinnedKey(key)", "pin controller action")
    require(bottom, "onAppCloseRequested: key => win.closeDockKey(key)", "close controller action")
    require(bottom, "onAppCycleRequested: (key, direction) => win.cycleDockKey(key, direction)", "cycle controller action")
    require(bottom, "onCalendarRequested: hubRoot.openCalendarFor(win.modelData)", "calendar controller action")
    if "toggleOverviewFor" in bottom or 'icon: "view_quilt"' in mode:
        raise SystemExit("FAIL: overview control must not be present in BottomHub")

    require(button, "property int buttonSize: 48", "button size parameter")
    require(button, "property int iconSize:", "button icon size parameter")
    require(button, 'property string imageSource: ""', "image button support")
    require(button, "property bool tooltipOnHover: true", "tooltip hover policy")
    require(button, "signal wheel(real delta)", "wheel interaction support")
    require(button, "property color activeColor:", "button active color parameter")
    require(button, "property color iconColor:", "button icon color parameter")
    require(button, "readonly property bool hovered: mouse.containsMouse", "hover state exposure")
    require(button, "CortetsuIcon {", "first-party icon primitive")
    if "MaterialIcon" in button or "Tokens." in button or "Colours." in button:
        raise SystemExit("FAIL: HubButton still depends on inherited Material visuals")

    print("BottomHub v3 semantic tests: OK")


if __name__ == "__main__":
    main()
