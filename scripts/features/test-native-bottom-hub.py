#!/usr/bin/env python3
from __future__ import annotations

import argparse
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
controller_path = modules / "BottomHub.qml"

FIRST_PARTY_FILES = (
    "CortetsuBottomHubView.qml",
    "CortetsuModeSegment.qml",
    "CortetsuWorkspaceDots.qml",
    "CortetsuAppRail.qml",
    "CortetsuTraySegment.qml",
    "CortetsuStatusSegment.qml",
    "HubButton.qml",
    "StatusPill.qml",
    "CortetsuIcon.qml",
    "CortetsuText.qml",
    "CortetsuSurface.qml",
    "CortetsuTypography.js",
)

FORBIDDEN_VIEW_TOKENS = (
    "Hyprland.",
    "SystemTray.",
    "Audio.",
    "Nmcli.",
    "Bluetooth.",
    "UPower.",
    "Notifs.",
    "Recorder.",
    "DesktopEntries.",
    "GlobalConfig.",
    "Apps.",
    "\nWallpapers.",
    "qs.services",
    "Caelestia.Config",
    "Quickshell.Bluetooth",
    "Quickshell.Services.UPower",
    "Quickshell.Services.SystemTray",
    "Colours.",
    "Tokens.",
    "StyledRect",
    "StyledText",
    "MaterialIcon",
    "ColouredIcon",
)

FORBIDDEN_CONTROLLER_VISUALS = (
    "Colours.",
    "Tokens.",
    "StyledRect",
    "StyledText",
    "MaterialIcon",
    "ColouredIcon",
    "CortetsuDesign",
    "CortetsuSurface {",
    "HubButton {",
    "StatusPill {",
)


def read(path: Path) -> str:
    assert path.is_file(), f"missing Bottom Hub file: {path}"
    return path.read_text(encoding="utf-8")


def assert_controller(text: str) -> None:
    assert text.count("CortetsuBottomHubView {") == 1
    assert "CortetsuWorkspaceDots {" not in text
    assert "CortetsuAppRail {" not in text
    assert "CortetsuTraySegment {" not in text
    assert "CortetsuStatusSegment {" not in text

    for token in FORBIDDEN_CONTROLLER_VISUALS:
        assert token not in text, f"BottomHub controller leaked visual primitive: {token}"

    for fingerprint in (
        'target: "bottomHub"',
        'target: "customDock"',
        "function togglePinned(item): void",
        "function focusWindowNow(client): void",
        "function closeWindow(client): void",
        "function activateItem(item): void",
        "function cycleItem(item, direction): void",
        "function showTrayMenu(itemId, centerX): void",
        "function activateTrayItem(itemId, secondary = false): void",
        "function toggleSession(): void",
        "CortetsuConfig.favouriteApps",
        "SystemTray.items.values",
        "Apps.launch(item.entry)",
        "CortetsuHypr.dispatch(",
        "Audio.incrementVolume()",
        "Audio.decrementVolume()",
        "CortetsuNetwork.activeEthernet",
        "Bluetooth.devices.values",
        "CortetsuPower",
        "CortetsuRecorder.stop()",
        "CortetsuNotifications.dnd = !CortetsuNotifications.dnd",
        "CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled",
        "hubRoot.toggleLauncherFor(win.modelData)",
        "hubRoot.openWallpaperFor(win.modelData)",
        "hubRoot.toggleClipboardFor(win.modelData)",
        "hubRoot.toggleSidebarFor(win.modelData)",
    ):
        assert fingerprint in text, f"BottomHub controller lost behavior: {fingerprint}"

    toaster = (repo / "cortetsu/services/CortetsuToaster.qml").read_text(encoding="utf-8")
    assert "/cortetsu/pomodoro-notification.json" in text
    assert "/cortetsu/pomodoro-notification.json" not in toaster
    assert "/caelestia/pomodoro-notification.json" not in toaster
    assert "focusable: true" in text
    assert "WlrKeyboardFocus.OnDemand" in text


def assert_view_file(path: Path, text: str) -> None:
    for token in FORBIDDEN_VIEW_TOKENS:
        assert token not in text, f"{path.name} leaked backend/legacy visual dependency: {token}"


def assert_view_contract(source: dict[str, str]) -> None:
    view = source["CortetsuBottomHubView.qml"]
    for component in (
        "CortetsuModeSegment {",
        "CortetsuAppRail {",
        "CortetsuTraySegment {",
        "CortetsuStatusSegment {",
    ):
        assert view.count(component) == 1, f"Bottom Hub view must own exactly one {component}"

    mode = source["CortetsuModeSegment.qml"]
    assert mode.count("CortetsuWorkspaceDots {") == 1
    assert "signal launcherRequested()" in mode
    assert "signal wallpaperRequested()" in mode
    assert "signal clipboardRequested()" in mode
    assert "required property bool clipboardActive" in mode
    assert 'import "CortetsuTypography.js" as CortetsuTypography' in mode
    assert 'icon: "content_paste_search"' in mode
    assert "signal workspaceRequested(int workspaceId)" in mode
    assert "width: implicitWidth" in mode
    assert "height: implicitHeight" in mode

    workspace = source["CortetsuWorkspaceDots.qml"]
    assert "signal workspaceRequested(int workspaceId)" in workspace
    assert "CortetsuDesign.motionStandardMs" in workspace
    assert "function focusWorkspace(workspaceId): void" in workspace
    assert "function activateWorkspace(workspaceId): void" in workspace
    assert "restoreFocus.workspaceId = workspaceId" in workspace
    assert "restoreFocus.restart()" in workspace
    assert "onTriggered: root.focusWorkspace(workspaceId)" in workspace

    rail = source["CortetsuAppRail.qml"]
    for signal in (
        "signal activateRequested(string key)",
        "signal togglePinnedRequested(string key)",
        "signal closeRequested(string key)",
        "signal cycleRequested(string key, int direction)",
    ):
        assert signal in rail
    assert "hovered: appMouse.containsMouse" in rail
    assert "scale: appMouse" not in rail
    assert "width: implicitWidth" in rail
    assert "modelData.title" in rail
    assert "CortetsuTooltip" in rail
    assert "onPressed: appItem.forceActiveFocus()" in rail

    tray = source["CortetsuTraySegment.qml"]
    assert "signal hoverRequested(string itemId, real centerX)" in tray
    assert "signal activateRequested(string itemId)" in tray
    assert "signal secondaryRequested(string itemId)" in tray
    assert "width: visible ? implicitWidth : 0" in tray
    assert "modelData.title" in tray
    assert "CortetsuTooltip" in tray
    assert "onPressed: trayItem.forceActiveFocus()" in tray
    assert "baseColor: CortetsuDesign.colorTetsu" in tray
    assert "CortetsuTooltip" in tray

    status = source["CortetsuStatusSegment.qml"]
    for signal in (
        "signal attachedControlRequested(string mode, real centerX)",
        "signal detachedControlRequested(string mode)",
        "signal volumeMuteRequested()",
        "signal notificationsRequested()",
        "signal calendarRequested()",
        "signal sessionRequested()",
    ):
        assert signal in status
    assert "StatusPill {" in status
    assert "width: implicitWidth" in status
    assert 'root.notificationCount > 9 ? qsTr("9+")' in status
    assert "onPressed: parent.forceActiveFocus()" in status

    button = source["HubButton.qml"]
    assert "CortetsuIcon {" in button
    assert "CortetsuSurface {" in button
    assert "CortetsuDesign.hoverScale" in button
    assert "onPressed: root.forceActiveFocus()" in button

    pill = source["StatusPill.qml"]
    assert "CortetsuIcon {" in pill
    assert "CortetsuText {" in pill
    assert "MaterialIcon" not in pill
    assert "StyledText" not in pill
    assert "onPressed: item.forceActiveFocus()" in pill

    icon = source["CortetsuIcon.qml"]
    assert 'CortetsuTypography.iconFamily' in icon
    assert 'property font fontStyle' in icon
    text = source["CortetsuText.qml"]
    assert 'font.family: CortetsuTypography.uiFamily' in text


def load_source_contract() -> tuple[str, dict[str, str]]:
    controller = read(controller_path)
    views: dict[str, str] = {}
    for name in FIRST_PARTY_FILES:
        path = modules / name
        text = read(path)
        assert_view_file(path, text)
        views[name] = text
    return controller, views


parser = argparse.ArgumentParser()
parser.add_argument("--runtime", type=Path)
args = parser.parse_args()

controller, views = load_source_contract()
assert_controller(controller)
assert_view_contract(views)

compiler = repo / "cortetsu/bin/native-bottom-hub.py"
assert not compiler.exists(), "transitional native-bottom-hub.py compiler must be retired"

if args.runtime:
    runtime_controller = read(args.runtime)
    assert runtime_controller == controller, "runtime BottomHub.qml must be the first-party source verbatim"
    runtime_modules = args.runtime.parent
    for name, expected in views.items():
        actual = read(runtime_modules / name)
        assert actual == expected, f"runtime {name} drifted from first-party source"

print("PASS: Bottom Hub presentation is fully first-party; BottomHub.qml is controller-only and compiler-free")
