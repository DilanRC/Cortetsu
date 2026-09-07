import QtQuick
import Quickshell
import qs.modules.bar as Bar
import qs.modules.dashboard as Dashboard
import qs.modules.launcher as Launcher
import qs.modules.overview as Overview
import qs.modules.notifications as Notifications
import qs.modules.osd as Osd
import qs.modules.session as Session
import qs.modules.sidebar as Sidebar
import ".."
import "../../components"
import qs.modules.utilities as Utilities
import qs.modules.bar.popouts as BarPopouts
import "../CortetsuDesign.js" as CortetsuDesign
import qs.modules.clipboard as Clipboard
import qs.modules.hardware as Hardware
import qs.modules.display as Display
import qs.modules.wallpaper as Wallpaper
import qs.modules.calendar as Calendar

Item {
    id: root
    required property ShellScreen screen
    required property ScreenState screenState
    required property Bar.BarWrapper bar
    required property real borderThickness

    readonly property alias osd: osd
    readonly property alias osdWrapper: osdWrapper
    readonly property alias notifications: notifications
    readonly property alias session: session
    readonly property alias sessionWrapper: sessionWrapper
    readonly property alias launcher: launcher
    readonly property alias overview: overview
    readonly property alias calendar: calendar
    readonly property alias wallpaperManager: wallpaperManager
    readonly property alias displayManager: displayManager
    readonly property alias hardware: hardware
    readonly property alias clipboard: clipboard
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias sidebar: sidebar

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

    Component.onCompleted: CortetsuShellState.registerComponents(root.screen, root)
    Component.onDestruction: CortetsuShellState.unregisterComponents(root.screen, root)

    Item {
        id: osdWrapper
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: sessionWrapper.anchors.rightMargin + session.width * (1 - session.offsetScale)
        clip: session.visible
        implicitWidth: osd.implicitWidth * (1 - osd.offsetScale)
        implicitHeight: osd.implicitHeight
        Osd.Wrapper {
            id: osd
            screen: root.screen
            screenState: root.screenState
            sidebarOrSessionVisible: session.visible
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Notifications.Wrapper {
        id: notifications
        screenState: root.screenState
        sidebarPanel: sidebar
        osdPanel: osdWrapper
        sessionPanel: sessionWrapper
        utilitiesPanel: utilities
        anchors.top: parent.top
        anchors.right: parent.right
    }

    Item {
        id: sessionWrapper
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        clip: false
        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight
        Session.Wrapper {
            id: session
            screenState: root.screenState
            sidebarVisible: sidebar.visible
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher
        screen: root.screen
        screenState: root.screenState
        panels: root
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
    }
    Overview.Wrapper { id: overview; screen: root.screen; screenState: root.screenState; anchors.fill: parent }
    Clipboard.Wrapper { id: clipboard; screen: root.screen; screenState: root.screenState; anchors.fill: parent }
    Hardware.Wrapper { id: hardware; screen: root.screen; screenState: root.screenState; anchors.fill: parent }
    Display.Wrapper { id: displayManager; screen: root.screen; screenState: root.screenState; anchors.fill: parent }
    Wallpaper.Wrapper { id: wallpaperManager; screen: root.screen; screenState: root.screenState; anchors.fill: parent }
    Calendar.Wrapper {
        id: calendar
        screenState: root.screenState
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: bar.implicitHeight + CortetsuDesign.spacingStandard
    }
    Dashboard.Wrapper {
        id: dashboard
        visible: false
        screenState: root.screenState
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
    }
    BarPopouts.ClipWrapper { id: popoutsWrapper; screen: root.screen; borderThickness: root.borderThickness }
    BarPopouts.CortetsuWindowInfoPopup {
        id: windowInfo
        screen: root.screen
        client: CortetsuHypr.activeToplevel
        popouts: popoutsWrapper.content
        visible: popoutsWrapper.content.detachedMode === "winfo"
        anchors.centerIn: parent
        z: 100
    }
    Utilities.Wrapper {
        id: utilities
        screenState: root.screenState
        popouts: popoutsWrapper.content
        anchors.bottom: parent.bottom
        anchors.right: parent.right
    }
    Sidebar.Wrapper {
        id: sidebar
        screenState: root.screenState
        anchors.bottom: parent.bottom
        anchors.right: root.screenState.utilities ? utilities.left : parent.right
        anchors.rightMargin: root.screenState.utilities ? CortetsuDesign.spacingStandard : 0
    }
}
