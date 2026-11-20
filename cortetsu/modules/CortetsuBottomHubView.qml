import QtQuick
import Quickshell
import "../theme"
import "HubAnchor.js" as HubAnchor
import "WindowPreview.js" as WindowPreview

// The Hub's islands on one edge of a monitor. `anchor` (HubAnchor.js) says
// which edge and how they are packed: spread along it, or together at one
// end. A lateral Hub stacks the same islands; nothing is rotated.
//
// Positions that leave this item (popout anchors) are measured along the
// edge: x on a horizontal Hub, y on a lateral one.
Item {
    id: root

    property string anchor: HubAnchor.fallback
    // The anchor the islands are laid out for. It follows `anchor` with
    // the layout animations off: a Hub that changes edge is placed at once,
    // while islands that grow or appear on the same edge glide.
    property string layoutAnchor: HubAnchor.fallback
    property bool glide: false
    onAnchorChanged: {
        glide = false;
        layoutAnchor = anchor;
        glideOn.restart();
    }
    Component.onCompleted: {
        layoutAnchor = anchor;
        glideOn.restart();
    }
    // One shot after an edge change: the window takes its new size from the
    // compositor a moment later, and that reflow must not glide either.
    Timer {
        id: glideOn
        interval: 250
        onTriggered: root.glide = true
    }
    readonly property var place: HubAnchor.describe(layoutAnchor)
    // Towards the middle of the screen: where an engaged island leans.
    readonly property var inward: {
        const travel = HubAnchor.popoutTravel(layoutAnchor);
        return Qt.point(-travel.x, -travel.y);
    }
    readonly property bool vertical: place.vertical
    readonly property string tooltipPlacement: place.edge === "top" ? "below"
        : place.edge === "left" ? "right" : place.edge === "right" ? "left" : "above"
    // The largest tooltip any Hub control can show (CortetsuTooltip reports
    // it; it only grows). The window keeps that much room on its inner side,
    // outside its input mask, so a tooltip never lands on its own control.
    property size tooltipExtent: Qt.size(0, 0)
    // A popout or panel from the Hub is showing: its tooltips step aside so
    // none lands on it (CortetsuTooltip reads this from its host).
    readonly property bool tooltipsSuppressed: engagedPopout.length > 0 || statusPanelOpen || launcherActive
    readonly property real tooltipRoom: tooltipExtent.height <= 0 ? 0
        : (vertical ? tooltipExtent.width : tooltipExtent.height) + CortetsuDesign.spacingCompact + 6

    required property bool launcherActive
    required property int workspaceCount
    required property int workspaceDisplayType
    required property bool workspaceShowAppIcons
    required property bool workspaceMonochromeIcons
    property bool trayMonochromeIcons: false
    property var trayMenuKeyHandler: null
    property var appPreviewKeyHandler: null
    property string openPopoutName: ""
    // The popout showing on this screen, "" while none is or it is closing.
    property string engagedPopout: ""
    // A panel opened from the status island (notifications, calendar,
    // session) is showing on this screen.
    property bool statusPanelOpen: false
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
    signal appPreviewHoverRequested(string key, real centerX)
    signal appPreviewHoverEnded()
    signal appPreviewRequested(string key, real centerX)
    signal trayHoverRequested(string itemKey, real centerX)
    signal trayHoverEnded()
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
    readonly property Item traySegmentItem: traySegment
    readonly property Item appRailItem: appSegment
    readonly property Item launcherButton: leftSegment.launcherButtonItem

    // What the Hub takes from its edge.
    readonly property real thickness: Math.max(56, CortetsuDesign.rowHeight + 8)
    // The popouts the status island opens.
    readonly property var statusModes: ["audio", "network", "bluetooth", "battery", "kblayout", "lockstatus", "activewindow"]
    readonly property real edgeGap: 8
    // Between the three groups (Núcleo, Aplicaciones, Sistema), and between
    // the two islands of Sistema (tray and status), which belong together.
    // Settings → Hub: "compact" | "standard" | "airy". Optional so older
    // callers and tests keep the standard rhythm.
    property string spacing: "standard"
    readonly property real gap: spacing === "compact" ? 8 : spacing === "airy" ? 20 : 12
    readonly property real pairGap: spacing === "compact" ? 3 : spacing === "airy" ? 6 : 4
    // The order of the three groups along the edge, from its start:
    // a permutation of "core" (Núcleo), "apps" and "system" (tray + status).
    // Optional so older callers and tests keep the classic order.
    property var order: ["core", "apps", "system"]
    readonly property var groups: ["core", "apps", "system"].every(g => (order ?? []).includes(g)) && (order ?? []).length === 3
        ? order : ["core", "apps", "system"]

    implicitWidth: thickness
    implicitHeight: thickness

    // The islands the pointer can reach, in this item's coordinates. The
    // window's input mask is exactly these, so the air between two islands
    // belongs to whatever is behind the Hub.
    readonly property var islands: [leftSegment, appSegment, traySegment, statusSegment]
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
    readonly property real systemLength: trayLength + statusLength + (trayLength > 0 && statusLength > 0 ? pairGap : 0)
    // The visible groups end to end, without a gap after the last one.
    readonly property real packedLength: {
        const steps = groupStep("core") + groupStep("apps") + groupStep("system");
        return Math.max(0, steps > 0 ? steps - gap : 0);
    }
    readonly property bool spread: place.pack === "spread"
    readonly property real packedStart: place.pack === "end" ? length - edgeGap - packedLength : edgeGap

    // Every position below is read from lengths only, never from another
    // island's position: a pack, edge or order change cannot form a loop.
    function groupLength(group: string): real {
        return group === "core" ? modeLength : group === "apps" ? appsLength : systemLength;
    }
    function groupStep(group: string): real {
        const size = groupLength(group);
        return size > 0 ? size + gap : 0;
    }
    // Spread: the first slot starts at the edge, the second is centred and
    // the third ends at the far edge, whatever group holds each. Packed: the
    // groups follow one another from packedStart.
    function groupAt(group: string): real {
        const slot = groups.indexOf(group);
        if (spread)
            return slot === 0 ? edgeGap
                : slot === 1 ? Math.round((length - groupLength(group)) / 2)
                : length - edgeGap - groupLength(group);
        let at = packedStart;
        for (let i = 0; i < slot; ++i)
            at += groupStep(groups[i]);
        return at;
    }

    readonly property real modeAt: groupAt("core")
    readonly property real appsAt: groupAt("apps")
    // Inside Sistema the tray comes first, then the status island.
    readonly property real trayAt: groupAt("system")
    readonly property real statusAt: trayAt + (trayLength > 0 ? trayLength + pairGap : 0)

    // The rail grows as far as its slot allows. Centred (spread, middle
    // slot): the longer neighbour bounds it on both sides. At a spread end:
    // up to the centred group. Packed: whatever the other groups leave.
    readonly property real appRailMaxWidth: {
        const others = groups.filter(group => group !== "apps");
        const slot = groups.indexOf("apps");
        if (spread && slot === 1)
            return Math.max(180, length - Math.max(groupLength(others[0]), groupLength(others[1])) * 2 - 64);
        if (spread)
            return Math.max(180, (length - groupLength(groups[1])) / 2 - edgeGap - gap * 2);
        return Math.max(180, length - edgeGap * 2 - groupStep(others[0]) - groupStep(others[1]));
    }

    // An engaged island leans 2 px towards its popout; islands that grow
    // or appear glide to their new place (layoutAnchor keeps an edge change
    // instant). Durations are motion tokens, so reduced motion is instant.
    CortetsuModeSegment {
        id: leftSegment

        engaged: root.launcherActive
        transform: HubLean { engaged: leftSegment.engaged; inward: root.inward }
        // design-lint: allow motion-layout-property: an island glides to the place its neighbours left it; the input mask follows
        Behavior on x { enabled: root.glide; HubGlide {} }
        // design-lint: allow motion-layout-property: same glide along a lateral Hub
        Behavior on y { enabled: root.glide; HubGlide {} }

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

        engaged: root.engagedPopout.startsWith(WindowPreview.prefix)
        transform: HubLean { engaged: appSegment.engaged; inward: root.inward }
        // design-lint: allow motion-layout-property: an island glides to the place its neighbours left it; the input mask follows
        Behavior on x { enabled: root.glide; HubGlide {} }
        // design-lint: allow motion-layout-property: same glide along a lateral Hub
        Behavior on y { enabled: root.glide; HubGlide {} }

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
        previewKeyHandler: root.appPreviewKeyHandler
        onPreviewHoverRequested: (key, centerX) => root.appPreviewHoverRequested(key, root.appsAt + centerX)
        onPreviewHoverEnded: root.appPreviewHoverEnded()
        onPreviewRequested: (key, centerX) => root.appPreviewRequested(key, root.appsAt + centerX)
    }

    CortetsuTraySegment {
        id: traySegment

        engaged: root.engagedPopout.startsWith("traymenu")
        transform: HubLean { engaged: traySegment.engaged; inward: root.inward }
        // design-lint: allow motion-layout-property: an island glides to the place its neighbours left it; the input mask follows
        Behavior on x { enabled: root.glide; HubGlide {} }
        // design-lint: allow motion-layout-property: same glide along a lateral Hub
        Behavior on y { enabled: root.glide; HubGlide {} }

        visible: root.trayVisible && root.trayItems.length > 0
        vertical: root.vertical
        tooltipPlacement: root.tooltipPlacement
        x: root.vertical ? root.across(traySegment) : root.trayAt
        y: root.vertical ? root.trayAt : root.across(traySegment)
        items: root.trayItems
        delegateModel: root.trayDelegateModel
        monochromeIcons: root.trayMonochromeIcons
        menuKeyHandler: root.trayMenuKeyHandler
        openPopoutName: root.openPopoutName
        onHoverRequested: (itemKey, centerX) => root.trayHoverRequested(itemKey, root.trayAt + centerX)
        onHoverEnded: root.trayHoverEnded()
        onActivateRequested: itemKey => root.trayActivateRequested(itemKey)
        onSecondaryActivateRequested: itemKey => root.traySecondaryActivateRequested(itemKey)
        onScrollRequested: (itemKey, delta, horizontal) =>
            root.trayScrollRequested(itemKey, delta, horizontal)
        onSecondaryRequested: (itemKey, centerX) => root.traySecondaryRequested(itemKey, root.trayAt + centerX)
    }

    CortetsuStatusSegment {
        id: statusSegment

        engaged: root.statusPanelOpen || root.statusModes.includes(root.engagedPopout)
        transform: HubLean { engaged: statusSegment.engaged; inward: root.inward }
        // design-lint: allow motion-layout-property: an island glides to the place its neighbours left it; the input mask follows
        Behavior on x { enabled: root.glide; HubGlide {} }
        // design-lint: allow motion-layout-property: same glide along a lateral Hub
        Behavior on y { enabled: root.glide; HubGlide {} }

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
