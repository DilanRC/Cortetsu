import QtQuick
import "CortetsuDesign.js" as CortetsuDesign

Item {
    id: root

    required property bool launcherActive
    required property bool wallpaperActive
    required property string wallpaperSource
    required property int workspaceCount
    required property int workspaceOffset
    required property int activeWsId
    required property var occupiedWorkspaceIds
    required property var dockItems
    required property var trayItems

    required property string volumeIcon
    required property bool volumeMuted
    required property string networkIcon
    required property string networkTooltip
    required property bool networkActive
    required property string bluetoothIcon
    required property bool bluetoothActive
    required property string batteryIcon
    required property bool batteryCritical
    required property string batteryTooltip
    required property int notificationCount
    required property bool sidebarActive
    required property bool recordingActive
    required property bool dndActive
    required property bool idleInhibited
    required property date now
    required property bool sessionActive

    signal launcherRequested()
    signal wallpaperRequested()
    signal workspaceRequested(int workspaceId)
    signal appActivateRequested(string key)
    signal appTogglePinnedRequested(string key)
    signal appCloseRequested(string key)
    signal appCycleRequested(string key, int direction)
    signal trayHoverRequested(string itemId, real centerX)
    signal trayActivateRequested(string itemId)
    signal traySecondaryRequested(string itemId)
    signal attachedControlRequested(string mode, real centerX)
    signal attachedControlEntered(string mode, real centerX)
    signal attachedControlExited()
    signal detachedControlRequested(string mode)
    signal volumeMuteRequested()
    signal volumeWheel(real delta)
    signal notificationsRequested()
    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()
    signal calendarRequested()
    signal sessionRequested()

    readonly property real rightOccupiedWidth:
        statusSegment.width + (traySegment.visible ? traySegment.width + 6 : 0)
    readonly property real appRailMaxWidth: Math.max(
        180,
        width - Math.max(leftSegment.width, rightOccupiedWidth) * 2 - 64
    )

    implicitHeight: 60

    // The dock is one restrained steel surface; individual segments keep
    // their own hierarchy only for interaction, keyboard focus and anchoring.
    CortetsuSurface {
        id: dockBackdrop

        anchors.fill: parent
        radiusValue: 0
        baseColor: Qt.alpha(CortetsuDesign.colorSumi, 0.9)
        outlined: false
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 1
        color: Qt.alpha(CortetsuDesign.colorWashi, 0.16)
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.alpha(CortetsuDesign.colorSumi, 0.72)
    }

    CortetsuModeSegment {
        id: leftSegment

        anchors.left: parent.left
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        launcherActive: root.launcherActive
        wallpaperActive: root.wallpaperActive
        wallpaperSource: root.wallpaperSource
        workspaceCount: root.workspaceCount
        workspaceOffset: root.workspaceOffset
        activeWsId: root.activeWsId
        occupiedWorkspaceIds: root.occupiedWorkspaceIds
        onLauncherRequested: root.launcherRequested()
        onWallpaperRequested: root.wallpaperRequested()
        onWorkspaceRequested: workspaceId => root.workspaceRequested(workspaceId)
    }

    CortetsuAppRail {
        id: appSegment

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        items: root.dockItems
        maxWidth: root.appRailMaxWidth
        onActivateRequested: key => root.appActivateRequested(key)
        onTogglePinnedRequested: key => root.appTogglePinnedRequested(key)
        onCloseRequested: key => root.appCloseRequested(key)
        onCycleRequested: (key, direction) => root.appCycleRequested(key, direction)
    }

    CortetsuTraySegment {
        id: traySegment

        anchors.right: statusSegment.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        items: root.trayItems
        onHoverRequested: (itemId, centerX) => root.trayHoverRequested(
            itemId,
            traySegment.x + centerX
        )
        onActivateRequested: itemId => root.trayActivateRequested(itemId)
        onSecondaryRequested: itemId => root.traySecondaryRequested(itemId)
    }

    CortetsuStatusSegment {
        id: statusSegment

        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        volumeIcon: root.volumeIcon
        volumeMuted: root.volumeMuted
        networkIcon: root.networkIcon
        networkTooltip: root.networkTooltip
        networkActive: root.networkActive
        bluetoothIcon: root.bluetoothIcon
        bluetoothActive: root.bluetoothActive
        batteryIcon: root.batteryIcon
        batteryCritical: root.batteryCritical
        batteryTooltip: root.batteryTooltip
        notificationCount: root.notificationCount
        sidebarActive: root.sidebarActive
        recordingActive: root.recordingActive
        dndActive: root.dndActive
        idleInhibited: root.idleInhibited
        now: root.now
        sessionActive: root.sessionActive
        onAttachedControlRequested: (mode, centerX) => root.attachedControlRequested(
            mode,
            statusSegment.x + centerX
        )
        onAttachedControlEntered: (mode, centerX) => root.attachedControlEntered(
            mode,
            statusSegment.x + centerX
        )
        onAttachedControlExited: root.attachedControlExited()
        onDetachedControlRequested: mode => root.detachedControlRequested(mode)
        onVolumeMuteRequested: root.volumeMuteRequested()
        onVolumeWheel: delta => root.volumeWheel(delta)
        onNotificationsRequested: root.notificationsRequested()
        onStopRecordingRequested: root.stopRecordingRequested()
        onToggleDndRequested: root.toggleDndRequested()
        onToggleIdleInhibitorRequested: root.toggleIdleInhibitorRequested()
        onCalendarRequested: root.calendarRequested()
        onSessionRequested: root.sessionRequested()
    }
}
