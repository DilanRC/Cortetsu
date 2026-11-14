import QtQuick
import Quickshell
import "../theme"

Item {
    id: root

    // A popout or panel opened from this island is showing (CortetsuIsland).
    property bool engaged: false

    required property bool launcherActive
    required property int workspaceCount
    required property int workspaceDisplayType
    required property bool workspaceShowAppIcons
    required property bool workspaceMonochromeIcons
    required property var workspaceAppIconSources
    required property int workspaceOffset
    required property int activeWsId
    required property var occupiedWorkspaceIds

    property bool vertical: false
    property string tooltipPlacement: "above"
    // What the island takes across the Hub, whichever way it runs.
    readonly property real thickness: Math.max(46, CortetsuDesign.rowHeight - 2)

    signal launcherRequested()
    signal workspaceRequested(int workspaceId)
    readonly property Item launcherButtonItem: launcherButton

    implicitWidth: vertical ? thickness : content.implicitWidth + 18
    implicitHeight: vertical ? content.implicitHeight + 18 : thickness
    width: implicitWidth
    height: implicitHeight

    CortetsuIsland {}

    HubFlow {
        id: content
        anchors.centerIn: parent
        vertical: root.vertical
        spacing: 2

        HubButton {
            id: launcherButton
            buttonSize: 44
            evolvingMarkPhase: root.launcherActive || launcherButton.pressed
                ? "Monster"
                : launcherButton.hovered || launcherButton.activeFocus
                    ? "Awakening"
                    : "Human"
            active: root.launcherActive
            tooltip: qsTr("Aplicaciones")
            tooltipPlacement: root.tooltipPlacement
            onClicked: root.launcherRequested()
        }

        Rectangle {
            width: root.vertical ? 22 : 1
            height: root.vertical ? 1 : 22
            color: Qt.alpha(CortetsuDesign.colorMuted, 0.14)
        }

        CortetsuWorkspaceDots {
            vertical: root.vertical
            workspaceCount: root.workspaceCount
            displayType: root.workspaceDisplayType
            showAppIcons: root.workspaceShowAppIcons
            monochromeAppIcons: root.workspaceMonochromeIcons
            appIconSources: root.workspaceAppIconSources
            workspaceOffset: root.workspaceOffset
            activeWsId: root.activeWsId
            occupiedWorkspaceIds: root.occupiedWorkspaceIds
            onWorkspaceRequested: workspaceId => root.workspaceRequested(workspaceId)
        }
    }
}
