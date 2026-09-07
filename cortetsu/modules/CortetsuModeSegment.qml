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

    signal launcherRequested()
    signal wallpaperRequested()
    signal workspaceRequested(int workspaceId)

    implicitWidth: content.implicitWidth + CortetsuDesign.spacingStandard
    implicitHeight: 52
    width: implicitWidth
    height: implicitHeight

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceHigh, 0.72)
        outlineColor: Qt.alpha(CortetsuDesign.colorMuted, 0.2)
        outlined: true
    }

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 3

        HubButton {
            buttonSize: 44
            imageSource: "file:///usr/share/icons/cachyos.svg"
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
            height: 24
            radius: 1
            color: Qt.alpha(CortetsuDesign.colorMuted, 0.18)
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
