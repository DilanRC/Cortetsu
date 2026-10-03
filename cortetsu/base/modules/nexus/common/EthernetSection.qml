pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus
import qs.modules.nexus.common

ColumnLayout {
    id: root

    required property NexusState nState
    required property int cappedWidth

    spacing: CortetsuTokens.spacing.extraSmall / 2

    ConnectedRect {
        Layout.fillWidth: true
        first: true
        implicitHeight: ethHeaderLayout.implicitHeight + CortetsuTokens.padding.medium * 2

        RowLayout {
            id: ethHeaderLayout

            anchors.fill: parent
            anchors.margins: CortetsuTokens.padding.medium
            anchors.leftMargin: CortetsuTokens.padding.largeIncreased
            anchors.rightMargin: CortetsuTokens.padding.largeIncreased
            spacing: CortetsuTokens.spacing.medium

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Ethernet")
                font: CortetsuTokens.font.body.medium
            }

            ColumnLayout {
                Layout.alignment: Qt.AlignRight
                spacing: 0

                CortetsuText {
                    Layout.alignment: Qt.AlignRight
                    text: Connectivity.wifi.activeEthernet ? qsTr("Connected") : qsTr("Not connected")
                    color: Connectivity.wifi.activeEthernet ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.label.small
                }

                CortetsuText {
                    Layout.alignment: Qt.AlignRight
                    visible: Connectivity.wifi.activeEthernet && false
                    text: qsTr("Data usage: %1").arg("")
                    color: CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.label.small
                }
            }
        }
    }

    Repeater {
        id: ethRepeater

        model: ScriptModel {
            values: Connectivity.wifi.devices.filter(d => d.type === DeviceType.Wired)
        }

        delegate: ConnectedRect {
            id: ethRow

            required property var modelData
            required property int index
            Component.onCompleted: Connectivity.wifi.refreshDetails(modelData.name)

            readonly property bool isConnected: modelData.connected
            // IP/MAC/DNS come from the parsed device details, not the basic
            // device list (which leaves those fields blank).
            readonly property var details: Connectivity.wifi.details[modelData.name] ?? null

            Layout.fillWidth: true
            last: index === ethRepeater.count - 1
            implicitHeight: ethLayout.implicitHeight + CortetsuTokens.padding.medium * 2

            // Tap opens the detail page for this interface.
            CortetsuStateLayer {
                onClicked: {
                    root.nState.selectedEthernetInterface = ethRow.modelData.name;
                    root.nState.selectedEthernetUuid = ethRow.details?.uuid ?? "";
                    root.nState.openSubPage(1);
                }
            }

            RowLayout {
                id: ethLayout

                anchors.fill: parent
                anchors.margins: CortetsuTokens.padding.medium
                anchors.leftMargin: CortetsuTokens.padding.largeIncreased
                anchors.rightMargin: CortetsuTokens.padding.medium
                spacing: CortetsuTokens.spacing.medium

                CortetsuSurface {
                    implicitWidth: implicitHeight
                    implicitHeight: ethIcon.implicitHeight + CortetsuTokens.padding.small * 2
                    radius: CortetsuTokens.rounding.full
                    color: ethRow.isConnected ? CortetsuColours.palette.m3primaryContainer : CortetsuColours.palette.m3surfaceContainerHighest

                    CortetsuIcon {
                        id: ethIcon

                        anchors.centerIn: parent
                        text: ethRow.isConnected ? "lan" : "settings_ethernet"
                        fill: text === "lan" ? 1 : 0
                        color: ethRow.isConnected ? CortetsuColours.palette.m3onPrimaryContainer : CortetsuColours.palette.m3onSurfaceVariant
                        fontStyle: CortetsuTokens.font.icon.medium
                        animate: true
                    }
                }

                // Name + interface
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    CortetsuText {
                        Layout.fillWidth: true
                        text: ethRow.details?.profileName || ethRow.modelData.name || qsTr("Wired connection")
                        font: CortetsuTokens.font.body.medium
                        elide: Text.ElideRight
                        animate: true
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: ethRow.isConnected ? ethRow.modelData.name : qsTr("Not connected • %1").arg(ethRow.modelData.name)
                        color: ethRow.isConnected ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3onSurfaceVariant
                        font: CortetsuTokens.font.label.small
                        elide: Text.ElideRight
                        animate: true
                    }
                }

                Item {
                    Layout.rightMargin: CortetsuTokens.spacing.small
                    opacity: ethRow.isConnected && root?.cappedWidth > CortetsuTokens.sizes.nexus.networkShowEthDetailWidth ? 1 : 0
                    visible: opacity > 0

                    implicitWidth: ethRow.isConnected && root?.cappedWidth > CortetsuTokens.sizes.nexus.networkShowEthDetailWidth ? ethDetailRow.implicitWidth : 0
                    implicitHeight: ethDetailRow.implicitHeight

                    Behavior on opacity {
                        Anim {
                            type: Anim.DefaultEffects
                        }
                    }

                    RowLayout {
                        id: ethDetailRow

                        anchors.right: parent.right
                        spacing: CortetsuTokens.spacing.large

                        EthDetail {
                            id: ethIpAddr

                            label: qsTr("Local IP Address")
                            value: ethRow.details?.address ?? ""
                        }

                        EthDetail {
                            id: ethDns

                            label: qsTr("Primary DNS")
                            value: ethRow.details?.dns?.[0] ?? ""
                        }
                    }
                }

                // Connect / disconnect
                IconButton {
                    type: IconButton.Tonal
                    enabled: !Connectivity.wifi.busy && (ethRow.isConnected || Connectivity.wifi.profiles.some(profile => profile.type === "802-3-ethernet" && (!profile.interface || profile.interface === ethRow.modelData.name)))
                    isToggle: true
                    isRound: true
                    checked: ethRow.isConnected
                    icon: ethRow.isConnected ? "link_off" : "link"
                    onClicked: {
                        if (ethRow.isConnected)
                            Connectivity.wifi.disconnectWired(ethRow.modelData);
                        else
                            Connectivity.wifi.connectProfile(Connectivity.wifi.profiles.find(profile => profile.type === "802-3-ethernet" && (!profile.interface || profile.interface === ethRow.modelData.name))?.uuid ?? "", ethRow.modelData.name);
                    }
                }

                CortetsuIcon {
                    text: "chevron_right"
                    color: CortetsuColours.palette.m3onSurfaceVariant
                    fontStyle: CortetsuTokens.font.icon.small
                }
            }
        }
    }

    component EthDetail: ColumnLayout {
        id: ethDetail

        required property string label
        property string value

        visible: value.length > 0
        spacing: 0

        CortetsuText {
            Layout.alignment: Qt.AlignRight
            text: ethDetail.label
            color: CortetsuColours.palette.m3onSurfaceVariant
            font: CortetsuTokens.font.label.small
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }

        CortetsuText {
            Layout.alignment: Qt.AlignRight
            text: ethDetail.value
            color: CortetsuColours.palette.m3outline
            font: CortetsuTokens.font.label.small
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignRight
        }
    }
}
