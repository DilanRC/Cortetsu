import QtQuick
import Quickshell
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

    signal launcherRequested()
    signal wallpaperRequested()
    signal workspaceRequested(int workspaceId)

    implicitWidth: content.implicitWidth + CortetsuDesign.spacingCompact
    implicitHeight: 50
    width: implicitWidth
    height: implicitHeight

    Row {
        id: content
        anchors.centerIn: parent
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
            tooltip: qsTr("Applications")
            onClicked: root.launcherRequested()
        }

        HubButton {
            buttonSize: 40
            cropImage: true
            imageSource: root.wallpaperSource
            active: root.wallpaperActive
            tooltip: qsTr("Wallpaper manager")
            onClicked: root.wallpaperRequested()
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 1
            height: 22
            radius: 1
            color: Qt.alpha(CortetsuDesign.colorMuted, 0.14)
        }

        CortetsuWorkspaceDots {
            anchors.verticalCenter: parent.verticalCenter
            workspaceCount: root.workspaceCount
            workspaceOffset: root.workspaceOffset
            activeWsId: root.activeWsId
            occupiedWorkspaceIds: root.occupiedWorkspaceIds
            onWorkspaceRequested: workspaceId => root.workspaceRequested(workspaceId)
        }
    }
}
