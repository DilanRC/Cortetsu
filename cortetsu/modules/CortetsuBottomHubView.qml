import QtQuick
import Quickshell
import "../theme"
import "HubAnchor.js" as HubAnchor

// The Hub's islands on one edge of a monitor. `anchor` (HubAnchor.js) says
// which edge and how they are packed: spread along it, or together at one
// end. A lateral Hub stacks the same islands; nothing is rotated.
//
// Positions that leave this item (popout anchors) are measured along the
// edge: x on a horizontal Hub, y on a lateral one.
Item {
    id: root

    property string anchor: HubAnchor.fallback
    readonly property var place: HubAnchor.describe(anchor)
    readonly property bool vertical: place.vertical
    readonly property string tooltipPlacement: place.edge === "top" ? "below"
        : place.edge === "left" ? "right" : place.edge === "right" ? "left" : "above"

    required property bool launcherActive
    required property int workspaceCount
    required property int workspaceDisplayType
    required property bool workspaceShowAppIcons
    required property bool workspaceMonochromeIcons
    property bool trayMonochromeIcons: false
    required property var workspaceAppIconSources
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

    // What the Hub takes from its edge.
    readonly property real thickness: Math.max(56, CortetsuDesign.rowHeight + 8)
    readonly property real edgeGap: 8
    readonly property real gap: 6

    implicitWidth: thickness
    implicitHeight: thickness

    // The islands the pointer can reach, in this item's coordinates. The
    // window's input mask is exactly these, so the air between two islands
    // belongs to whatever is behind the Hub.
    readonly property var islands: [leftSegment, appSegment, traySegment, statusSegment]
    function islandRect(island: Item): rect {
        return island.visible ? Qt.rect(island.x, island.y, island.width, island.height) : Qt.rect(0, 0, 0, 0);
    }

    function along(item: Item): real { return !item.visible ? 0 : root.vertical ? item.height : item.width; }
    function across(item: Item): real {
        return Math.round(((root.vertical ? root.width : root.height) - (root.vertical ? item.width : item.height)) / 2);
    }
    function step(item: Item): real { return root.along(item) > 0 ? root.along(item) + root.gap : 0; }

    readonly property real length: vertical ? height : width
    readonly property real modeLength: along(leftSegment)
    readonly property real appsLength: along(appSegment)
    readonly property real trayLength: along(traySegment)
    readonly property real statusLength: along(statusSegment)
    readonly property real packedLength: Math.max(0, step(leftSegment) + step(appSegment) + step(traySegment) + step(statusSegment) - gap)
    readonly property bool spread: place.pack === "spread"
    readonly property real packedStart: place.pack === "end" ? length - edgeGap - packedLength : edgeGap

    readonly property real modeAt: spread ? edgeGap : packedStart
    readonly property real appsAt: spread ? Math.round((length - appsLength) / 2) : modeAt + step(leftSegment)
    readonly property real statusAt: spread ? length - edgeGap - statusLength : trayAt + step(traySegment)
    readonly property real trayAt: spread
        ? statusAt - (statusLength > 0 ? gap + 2 : 0) - trayLength
        : appsAt + step(appSegment)

    // Spread: the rail stays centred, so it may only grow as far as the
    // longer of its two neighbours allows on both sides. Packed: whatever
    // the other islands leave.
    readonly property real appRailMaxWidth: Math.max(180, spread
        ? length - Math.max(modeLength, statusLength + (trayLength > 0 ? trayLength + gap + 2 : 0)) * 2 - 64
        : length - edgeGap * 2 - step(leftSegment) - step(traySegment) - step(statusSegment))

    CortetsuModeSegment {
        id: leftSegment

        visible: root.modeVisible
        vertical: root.vertical
        tooltipPlacement: root.tooltipPlacement
        x: root.vertical ? root.across(leftSegment) : root.modeAt
        y: root.vertical ? root.modeAt : root.across(leftSegment)
        launcherActive: root.launcherActive
        workspaceCount: root.workspaceCount
        workspaceDisplayType: root.workspaceDisplayType
        workspaceShowAppIcons: root.workspaceShowAppIcons
        workspaceMonochromeIcons: root.workspaceMonochromeIcons
        workspaceAppIconSources: root.workspaceAppIconSources
        workspaceOffset: root.workspaceOffset
        activeWsId: root.activeWsId
        occupiedWorkspaceIds: root.occupiedWorkspaceIds
        onLauncherRequested: root.launcherRequested()
        onWorkspaceRequested: workspaceId => root.workspaceRequested(workspaceId)
    }

    CortetsuAppRail {
        id: appSegment

        visible: root.appsVisible && root.dockItems.length > 0
        vertical: root.vertical
        tooltipPlacement: root.tooltipPlacement
        x: root.vertical ? root.across(appSegment) : root.appsAt
        y: root.vertical ? root.appsAt : root.across(appSegment)
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
        vertical: root.vertical
        tooltipPlacement: root.tooltipPlacement
        x: root.vertical ? root.across(traySegment) : root.trayAt
        y: root.vertical ? root.trayAt : root.across(traySegment)
        items: root.trayItems
        delegateModel: root.trayDelegateModel
        monochromeIcons: root.trayMonochromeIcons
        onHoverRequested: (itemKey, centerX) => root.trayHoverRequested(itemKey, root.trayAt + centerX)
        onActivateRequested: itemKey => root.trayActivateRequested(itemKey)
        onSecondaryActivateRequested: itemKey => root.traySecondaryActivateRequested(itemKey)
        onScrollRequested: (itemKey, delta, horizontal) =>
            root.trayScrollRequested(itemKey, delta, horizontal)
        onSecondaryRequested: (itemKey, centerX) => root.traySecondaryRequested(itemKey, root.trayAt + centerX)
    }

    CortetsuStatusSegment {
        id: statusSegment

        visible: root.statusVisible
        vertical: root.vertical
        tooltipPlacement: root.tooltipPlacement
        x: root.vertical ? root.across(statusSegment) : root.statusAt
        y: root.vertical ? root.statusAt : root.across(statusSegment)
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
        onAttachedControlRequested: (mode, centerX) => root.attachedControlRequested(mode, root.statusAt + centerX)
        onAttachedControlEntered: (mode, centerX) => root.attachedControlEntered(mode, root.statusAt + centerX)
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
