import QtQuick
import Quickshell
import "../theme"

Item {
    id: root

    required property bool launcherActive
    required property int workspaceCount
    required property int workspaceDisplayType
    required property int workspaceOffset
    required property int activeWsId
    required property var occupiedWorkspaceIds
    required property var dockItems
    required property var trayItems
    readonly property var dockDelegateModel: ScriptModel {
        values: root.dockItems
        objectProp: "key"
    }
    readonly property var trayDelegateModel: ScriptModel {
        values: root.trayItems
        objectProp: "key"
    }
    required property bool modeVisible
    required property bool appsVisible
    required property bool trayVisible
    required property bool statusVisible

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
    required property bool audioVisible
    required property bool networkVisible
    required property bool bluetoothVisible
    required property bool batteryVisible
    required property bool statusPopoutsEnabled
    required property int notificationCount
    required property bool sidebarActive
    required property bool recordingActive
    required property bool dndActive
    required property bool idleInhibited
    required property date now
    required property bool sessionActive

    signal launcherRequested()
    signal workspaceRequested(int workspaceId)
    signal appActivateRequested(string key)
    signal appTogglePinnedRequested(string key)
    signal appCloseRequested(string key)
    signal appCycleRequested(string key, int direction)
    signal trayHoverRequested(string itemKey, real centerX)
    signal trayActivateRequested(string itemKey)
    signal traySecondaryActivateRequested(string itemKey)
    signal trayScrollRequested(string itemKey, int delta, bool horizontal)
    signal traySecondaryRequested(string itemKey, real centerX)
    signal attachedControlRequested(string mode, real centerX)
    signal attachedControlEntered(string mode, real centerX)
    signal systemControlsEntered()
    signal systemControlsExited()
    signal detachedControlRequested(string mode)
    signal volumeMuteRequested()
    signal volumeWheel(real delta)
    signal notificationsRequested()
    signal stopRecordingRequested()
    signal toggleDndRequested()
    signal toggleIdleInhibitorRequested()
    signal calendarRequested()
    signal sessionRequested()

    readonly property Item notificationsButton: statusSegment.notificationsButton
    readonly property Item launcherButton: leftSegment.launcherButtonItem

    readonly property real rightOccupiedWidth:
        (statusSegment.visible ? statusSegment.width : 0)
        + (traySegment.visible ? traySegment.width : 0)
        + (statusSegment.visible && traySegment.visible ? 6 : 0)
    readonly property real appRailMaxWidth: Math.max(
        180,
        width - Math.max(leftSegment.visible ? leftSegment.width : 0, rightOccupiedWidth) * 2 - 64
    )

    implicitHeight: 60

    // No backdrop: each segment is its own floating island (CortetsuIsland)
    // and the wallpaper shows between them.

    CortetsuModeSegment {
        id: leftSegment

        visible: root.modeVisible
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        launcherActive: root.launcherActive
        workspaceCount: root.workspaceCount
        workspaceDisplayType: root.workspaceDisplayType
        workspaceOffset: root.workspaceOffset
        activeWsId: root.activeWsId
        occupiedWorkspaceIds: root.occupiedWorkspaceIds
        onLauncherRequested: root.launcherRequested()
        onWorkspaceRequested: workspaceId => root.workspaceRequested(workspaceId)
    }

    CortetsuAppRail {
        id: appSegment

        visible: root.appsVisible && root.dockItems.length > 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        items: root.dockItems
        delegateModel: root.dockDelegateModel
        maxWidth: root.appRailMaxWidth
        onActivateRequested: key => root.appActivateRequested(key)
        onTogglePinnedRequested: key => root.appTogglePinnedRequested(key)
        onCloseRequested: key => root.appCloseRequested(key)
        onCycleRequested: (key, direction) => root.appCycleRequested(key, direction)
    }

    CortetsuTraySegment {
        id: traySegment

        visible: root.trayVisible && root.trayItems.length > 0
        anchors.right: statusSegment.visible ? statusSegment.left : parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        items: root.trayItems
        delegateModel: root.trayDelegateModel
        onHoverRequested: (itemKey, centerX) => root.trayHoverRequested(
            itemKey,
            traySegment.x + centerX
        )
        onActivateRequested: itemKey => root.trayActivateRequested(itemKey)
        onSecondaryActivateRequested: itemKey => root.traySecondaryActivateRequested(itemKey)
        onScrollRequested: (itemKey, delta, horizontal) =>
            root.trayScrollRequested(itemKey, delta, horizontal)
        onSecondaryRequested: (itemKey, centerX) => root.traySecondaryRequested(
            itemKey,
            traySegment.x + centerX
        )
    }

    CortetsuStatusSegment {
        id: statusSegment

        visible: root.statusVisible
        anchors.right: parent.right
        anchors.rightMargin: 8
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
        audioVisible: root.audioVisible
        networkVisible: root.networkVisible
        bluetoothVisible: root.bluetoothVisible
        batteryVisible: root.batteryVisible
        statusPopoutsEnabled: root.statusPopoutsEnabled
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
        onSystemControlsEntered: root.systemControlsEntered()
        onSystemControlsExited: root.systemControlsExited()
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
