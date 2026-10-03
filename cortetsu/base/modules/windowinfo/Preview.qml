pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.components
import qs.services

Item {
    id: root

    required property ShellScreen screen
    required property HyprlandToplevel client

    Layout.preferredWidth: preview.implicitWidth + CortetsuTokens.padding.extraLargeIncreased
    Layout.fillHeight: true

    StyledClippingRect {
        id: preview

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.bottom: label.top
        anchors.topMargin: CortetsuTokens.padding.large
        anchors.bottomMargin: CortetsuTokens.spacing.medium

        implicitWidth: view.implicitWidth

        color: CortetsuColours.tPalette.m3surfaceContainer
        radius: CortetsuTokens.rounding.medium

        Loader {
            asynchronous: true
            anchors.centerIn: parent
            active: !root.client

            sourceComponent: ColumnLayout {
                spacing: 0

                CortetsuIcon {
                    Layout.alignment: Qt.AlignHCenter
                    text: "web_asset_off"
                    color: CortetsuColours.palette.m3outline
                    fontStyle: CortetsuTokens.font.icon.builders.extraLarge.scale(3).build()
                }

                CortetsuText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("No active client")
                    color: CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.body.builders.large.size(28).weight(Font.Medium).build()
                }

                CortetsuText {
                    Layout.alignment: Qt.AlignHCenter
                    text: qsTr("Try switching to a window")
                    color: CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.body.large
                }
            }
        }

        ScreencopyView {
            id: view

            anchors.centerIn: parent

            captureSource: root.visible ? (root.client?.wayland ?? null) : null // qmllint disable unresolved-type
            live: visible

            constraintSize.width: root.client ? parent.height * Math.min(root.screen.width / root.screen.height, root.client?.lastIpcObject.size[0] / root.client?.lastIpcObject.size[1]) : parent.height
            constraintSize.height: parent.height
        }
    }

    CortetsuText {
        id: label

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: CortetsuTokens.padding.large

        animate: true
        text: {
            const client = root.client;
            if (!client)
                return qsTr("No active client");

            const mon = client.monitor;
            return qsTr("%1 on monitor %2 at %3, %4").arg(client.title).arg(mon.name).arg(client.lastIpcObject.at[0]).arg(client.lastIpcObject.at[1]);
        }
    }
}
