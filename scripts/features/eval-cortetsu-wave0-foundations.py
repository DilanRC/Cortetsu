#!/usr/bin/env python3
"""Small deterministic eval for Wave 0 coverage and scope boundaries."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text()
row = (ROOT / "cortetsu/components/CortetsuListRow.qml").read_text()
hub_button = (ROOT / "cortetsu/modules/HubButton.qml").read_text()
app_rail = (ROOT / "cortetsu/modules/CortetsuAppRail.qml").read_text()
tray = (ROOT / "cortetsu/modules/CortetsuTraySegment.qml").read_text()
status = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text()
status_pill = (ROOT / "cortetsu/modules/StatusPill.qml").read_text()
workspaces = (ROOT / "cortetsu/modules/CortetsuWorkspaceDots.qml").read_text()
state_message = (ROOT / "cortetsu/components/CortetsuStateMessage.qml").read_text()
toggle = (ROOT / "cortetsu/components/CortetsuToggle.qml").read_text()
slider = (ROOT / "cortetsu/components/CortetsuSlider.qml").read_text()
battery = (ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml").read_text()
keyboard = (ROOT / "cortetsu/modules/bar/popouts/CortetsuKeyboardPopup.qml").read_text()
winfo = (ROOT / "cortetsu/modules/bar/popouts/CortetsuWindowInfoPopup.qml").read_text()
notification = (ROOT / "cortetsu/modules/notifications/Notification.qml").read_text()
toast = (ROOT / "cortetsu/modules/utilities/toasts/ToastItem.qml").read_text()
sidebar = (ROOT / "cortetsu/modules/sidebar/Content.qml").read_text()
launcher_list = (ROOT / "cortetsu/modules/launcher/ContentList.qml").read_text()
launcher = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text()
overview = (ROOT / "cortetsu/modules/overview/Content.qml").read_text()
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text()

checks = {
    "button exposes focus": "focused: root.activeFocus" in button,
    "row exposes focus": "focused: root.activeFocus" in row,
    "hub button exposes focus": "focused: root.activeFocus" in hub_button,
    "app rail exposes focus": "focused: appItem.activeFocus" in app_rail,
    "tray exposes focus": "focused: trayItem.activeFocus" in tray,
    "status clock exposes focus": "focused: parent.activeFocus" in status,
    "status pill exposes focus": "focused: item.activeFocus" in status_pill,
    "workspace exposes focus": "workspaceDot.activeFocus" in workspaces,
    "state message covers async states": all(x in state_message for x in ('property string kind', 'kind === "loading"', 'kind === "error"')),
    "toggle supports keyboard": all(x in toggle for x in ("Keys.onEnterPressed", "Keys.onSpacePressed", "focused: root.activeFocus")),
    "slider supports keyboard": all(x in slider for x in ("Keys.onLeftPressed", "Keys.onRightPressed", "Qt.Key_Home", "Qt.Key_End")),
    "battery profile supports keyboard": all(
        x in battery
        for x in (
            "activeFocusOnTab: true",
            "onPressed: profileButton.forceActiveFocus()",
            "focused: profileButton.activeFocus",
            "Keys.onEnterPressed",
            "Keys.onSpacePressed",
        )
    ),
    "battery popup shares power surface and state icon": all(
        x in battery
        for x in (
            "CortetsuPopupSurface",
            "Icons.getBatteryIcon",
            "CortetsuPower.charging",
            'qsTr(\"Fully charged\")',
        )
    ),
    "keyboard popup exposes disabled layouts": "disabled: layoutIndex > 3" in keyboard,
    "window info disables unavailable actions": winfo.count("disabled: !root.client") >= 4,
    "notification supports keyboard": all(x in notification for x in ("activeFocusOnTab", "Keys.onEnterPressed", "Keys.onEscapePressed", "CortetsuButton")),
    "toast supports keyboard": all(x in toast for x in ("activeFocusOnTab", "Keys.onEnterPressed", "Keys.onEscapePressed")),
    "notification center has reusable empty states": sidebar.count("CortetsuStateMessage") >= 2,
    "launcher has reusable empty state": all(x in launcher_list for x in ("CortetsuStateMessage", "No wallpapers found", "No results")),
    "launcher distinguishes wallpaper loading": all(x in launcher_list for x in ("listLoading", 'kind: "loading"', "Loading wallpapers")),
    "launcher has product search hierarchy": all(
        x in launcher
        for x in (
            "CortetsuPopupSurface",
            'objectName: "launcherSearch"',
            'placeholderText: qsTr("Search apps or commands…")',
            "anchors.top: parent.top",
        )
    ),
    "overview has reusable empty state": all(x in overview for x in ("CortetsuStateMessage", "No windows to show", "Open an application")),
    "button supports keyboard": all(x in button for x in ("Keys.onEnterPressed", "Keys.onReturnPressed", "Keys.onSpacePressed")),
    "row supports keyboard": all(x in row for x in ("Keys.onEnterPressed", "Keys.onReturnPressed", "Keys.onSpacePressed")),
    "hub button supports keyboard": all(x in hub_button for x in ("Keys.onEnterPressed", "Keys.onReturnPressed", "Keys.onSpacePressed")),
    "app rail supports keyboard": all(x in app_rail for x in ("Keys.onEnterPressed", "Keys.onLeftPressed", "Keys.onRightPressed")),
    "tray supports keyboard": all(x in tray for x in ("Keys.onEnterPressed", "Keys.onMenuPressed")),
    "status clock supports keyboard": all(x in status for x in ("Keys.onEnterPressed", "Keys.onSpacePressed")),
    "status pill supports keyboard": all(x in status_pill for x in ("Keys.onEnterPressed", "Keys.onSpacePressed")),
    "workspace supports keyboard": all(x in workspaces for x in ("Keys.onEnterPressed", "Keys.onLeftPressed", "Keys.onRightPressed")),
    "popup controller untouched": "bottomAnchorCenter" in hub and "closeAllPopouts" in hub,
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: Wave 0 eval missing " + ", ".join(missing))

print(f"Wave 0 foundations eval: {len(checks)}/{len(checks)} (100%)")
