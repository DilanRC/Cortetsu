import QtQuick
import Quickshell
import "../bar" as Bar
import "../dashboard" as Dashboard
import "../launcher" as Launcher
import "../notifications" as Notifications
import "../osd" as Osd
import "../session" as Session
import "../sidebar" as Sidebar
import ".."
import "../../components"
import "../utilities" as Utilities
import "../bar/popouts" as BarPopouts
import "../../theme"
import "../HubAnchor.js" as HubAnchor

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
    readonly property alias dashboard: dashboard
    readonly property alias popouts: popoutsWrapper.content
    readonly property alias popoutsWrapper: popoutsWrapper
    readonly property alias utilities: utilities
    readonly property alias sidebar: sidebar

    // What the Hub takes from each edge of this screen. The panels that
    // share an edge with it stand clear by this much.
    readonly property var hubReserved: HubAnchor.reserved(
        CortetsuConfig.bottomHub.anchorFor(root.screen?.name ?? ""), CortetsuDesign.bottomHubHeight)

    anchors.fill: parent
    anchors.margins: borderThickness
    anchors.leftMargin: bar.implicitWidth

    Component.onCompleted: CortetsuShellState.registerComponents(root.screen, root)
    Component.onDestruction: CortetsuShellState.unregisterComponents(root.screen, root)

    Item {
        id: osdWrapper
        // Keep transient OSD cards clear of the Hub, wherever it sits.
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.hubReserved.bottom + CortetsuDesign.spacingStandard
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

    // The mini OSD: top centre of this monitor, under the Hub when the Hub
    // takes the top edge. It takes no pointer and no focus (no region in the
    // input mask), and is independent of where the control center opens.
    Osd.MiniSlider {
        id: miniOsd
        objectName: "miniOsd"
        readonly property bool shown: osd.miniShown
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: root.hubReserved.top + CortetsuDesign.spacingStandard - (shown ? 0 : 12)
        visible: opacity > 0
        opacity: shown ? 1 : 0
        z: 50
        kind: osd.compactKind
        value: osd.miniValue
        maximum: osd.miniMaximum
        available: osd.miniAvailable
        muted: osd.miniMuted
        name: osd.miniName
        detail: osd.miniDetail
        art: osd.miniArt

        Behavior on opacity {
            NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
        }
        Behavior on anchors.topMargin {
            NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic }
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
        // The same inset as the notification drawer on this edge
        // (sidebar/Wrapper.qml), so a card never touches the screen corner.
        anchors.topMargin: CortetsuDesign.spacingCompact + root.hubReserved.top
        anchors.rightMargin: CortetsuDesign.spacingCompact + root.hubReserved.right
    }

    Item {
        id: sessionWrapper
        visible: false
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: root.hubReserved.right
        clip: false
        implicitWidth: session.implicitWidth * (1 - session.offsetScale)
        implicitHeight: session.implicitHeight
    Session.Wrapper {
        id: session
        visible: false
            screenState: root.screenState
            sidebarVisible: sidebar.visible
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
        }
    }

    Launcher.Wrapper {
        id: launcher
        visible: false
        screen: root.screen
        screenState: root.screenState
        panels: root
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
    }
    Dashboard.Wrapper {
        id: dashboard
        visible: false
        screenState: root.screenState
        hubReserved: root.hubReserved
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
    // The notification center: as tall as its content, opening out of the
    // Hub's system island towards the middle of the screen, wherever the Hub
    // sits (HubAnchor.popoutPosition, the same rule as the attached popouts).
    Sidebar.Wrapper {
        id: sidebar
        readonly property string hubAnchorId: CortetsuConfig.bottomHub.anchorFor(root.screen?.name ?? "")
        // The island's position in screen coordinates, to this item's.
        readonly property real along: (root.screenState?.sidebarAlong ?? -1) < 0 ? -1
            : root.screenState.sidebarAlong - (HubAnchor.describe(hubAnchorId).vertical ? root.y : root.x)
        readonly property var spot: HubAnchor.popoutPosition(hubAnchorId, along, width, height,
            root.width, root.height, CortetsuDesign.bottomHubHeight, 8, 8)
        screenState: root.screenState
        hubReserved: root.hubReserved
        travel: HubAnchor.popoutTravel(hubAnchorId)
        availableHeight: root.height - 16 - root.hubReserved.top - root.hubReserved.bottom
        x: spot.x
        y: spot.y
    }
}
