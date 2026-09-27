pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Services.SystemTray
import qs.components.effects
import qs.modules
import qs.services
import qs.utils

MouseArea {
    id: root

    required property var modelData
    readonly property SystemTrayItem trayItem: modelData.item

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: CortetsuTokens.font.body.small.pointSize * 2
    implicitHeight: CortetsuTokens.font.body.small.pointSize * 2

    onClicked: event => {
        if (event.button === Qt.LeftButton)
            trayItem.activate();
        else
            trayItem.secondaryActivate();
    }

    ColouredIcon {
        id: icon

        anchors.fill: parent
        source: Icons.getTrayIcon(root.trayItem.id, root.trayItem.icon)
        colour: CortetsuColours.palette.m3secondary
        layer.enabled: CortetsuConfig.bar.tray.recolour
    }
}
