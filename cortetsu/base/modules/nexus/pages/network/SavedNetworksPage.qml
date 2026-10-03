pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.components
import qs.services
import qs.utils
import qs.modules.nexus.common

PageBase {
    id: root

    title: qsTr("Saved networks")
    isSubPage: true

    Component.onCompleted: Connectivity.wifi.refreshProfiles()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: CortetsuTokens.spacing.extraSmall / 2

        ItemList {
            id: savedList

            showList: true
            first: true
            last: true
            placeholderIcon: "wifi_find"
            placeholderText: qsTr("No saved networks")

            model: ScriptModel {
                values: Connectivity.wifi.profiles.filter(profile => profile.type === "802-11-wireless").slice().sort((a, b) => a.name.localeCompare(b.name))
            }

            delegate: CortetsuStateLayer {
                id: saved

                required property int index
                required property var modelData
                readonly property var ap: Connectivity.wifi.networks.find(network => network.name === modelData.ssid && (!modelData.interface || network.device.name === modelData.interface)) ?? null
                readonly property bool isActive: Connectivity.wifi.devices.some(device => Connectivity.wifi.details[device.name]?.uuid === modelData.uuid)

                anchors.left: savedList.list.contentItem.left
                anchors.right: savedList.list.contentItem.right
                implicitHeight: savedLayout.implicitHeight + savedLayout.anchors.margins * 2
                radius: CortetsuTokens.rounding.extraSmall
                topLeftRadius: index === 0 ? CortetsuTokens.rounding.extraLarge : radius
                topRightRadius: index === 0 ? CortetsuTokens.rounding.extraLarge : radius
                bottomLeftRadius: index === savedList?.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
                bottomRightRadius: index === savedList?.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
                anchors.fill: undefined

                onClicked: {
                    root.nState.selectedNetworkSsid = saved.modelData.ssid;
                    root.nState.selectedNetworkUuid = saved.modelData.uuid;
                    root.nState.selectedNetwork = saved.ap;
                    root.nState.networkDetailsFromSaved = true;
                    root.nState.openSubPage(3); // Shared network detail/edit sub-page
                }

                RowLayout {
                    id: savedLayout

                    anchors.fill: parent
                    anchors.margins: CortetsuTokens.padding.large
                    anchors.leftMargin: CortetsuTokens.padding.extraLarge
                    anchors.rightMargin: CortetsuTokens.padding.extraLarge
                    spacing: CortetsuTokens.spacing.medium

                    CortetsuIcon {
                        text: saved.ap ? Icons.getNetworkIcon(Math.round(saved.ap.signalStrength * 100), saved.ap.security !== WifiSecurityType.Open) : "signal_wifi_off"
                        color: saved.isActive ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3onSurfaceVariant
                        fontStyle: CortetsuTokens.font.icon.medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        CortetsuText {
                            Layout.fillWidth: true
                            text: saved.modelData.name
                            font: CortetsuTokens.font.body.small
                            elide: Text.ElideRight
                        }

                        CortetsuText {
                            Layout.fillWidth: true
                            text: {
                                let security;
                                if (saved.ap)
                                    security = WifiSecurityType.toString(saved.ap.security);
                                else
                                    security = saved.modelData.uuid;
                                if (saved.isActive)
                                    return qsTr("Connected • %1").arg(security);
                                return security;
                            }
                            color: saved.isActive ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3outline
                            font: CortetsuTokens.font.label.small
                            elide: Text.ElideRight
                        }
                    }

                    CortetsuIcon {
                        text: "chevron_right"
                        color: CortetsuColours.palette.m3onSurfaceVariant
                        fontStyle: CortetsuTokens.font.icon.medium
                    }
                }
            }
        }
    }
}
