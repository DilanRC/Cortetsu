pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Networking
import qs.components
import qs.components.controls
import qs.services
import qs.utils
import qs.modules.nexus

ItemList {
    id: root

    required property NexusState nState
    property int limit: 0 // 0 = show all
    property bool enableFilter

    signal networkSelected(ap: var)

    function networkFilter(ap: var): bool {
        return true;
    }

    showList: Connectivity.wifi.wifiEnabled
    placeholderIcon: Connectivity.wifi.wifiEnabled ? "wifi_find" : "signal_wifi_off"
    placeholderText: Connectivity.wifi.wifiEnabled ? qsTr("No networks found") : qsTr("Wi-Fi disabled")
    extraHeight: Connectivity.wifi.scanning ? CortetsuTokens.rounding.extraSmall : 0 // Inline so it isn't affected by anim
    list.anchors.top: scanningIndicator.bottom

    model: ScriptModel {
        values: {
            const connecting = Connectivity.wifi.operationNetwork;
            // Lower rank sorts higher in the list
            const rank = n => n.connected ? 0 : n === connecting ? 1 : n.known ? 2 : 3;
            const sorted = [...Connectivity.wifi.networks].sort((a, b) => rank(a) - rank(b) || b.signalStrength - a.signalStrength);
            if (root.limit > 0 && sorted.length > root.limit)
                sorted.length = root.limit;
            return root.enableFilter ? sorted.filter(root.networkFilter) : sorted;
        }
    }

    delegate: CortetsuStateLayer {
        id: network

        required property int index
        required property var modelData
        property bool currentSelected
        property real textOpacity: disabled ? 0.5 : 1

        disabled: Connectivity.wifi.busy && Connectivity.wifi.operationNetwork === modelData

        anchors.left: root.list.contentItem.left
        anchors.right: root.list.contentItem.right
        implicitHeight: networkLayout.implicitHeight + networkLayout.anchors.margins * 2
        radius: CortetsuTokens.rounding.extraSmall
        bottomLeftRadius: root?.last && index === root.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
        bottomRightRadius: root?.last && index === root.list.count - 1 ? CortetsuTokens.rounding.extraLarge : radius
        anchors.fill: undefined

        onClicked: {
            if (!modelData.connected) {
                if (modelData.known || modelData.security === WifiSecurityType.Open) Connectivity.wifi.connectNetwork(modelData, "", null);
                else { root.nState.selectedNetwork = modelData; root.nState.openSubPage(2); }
                currentSelected = true;
                root.networkSelected(modelData);
            } else {
                // Active network: open its detail/settings sub-page.
                root.nState.selectedNetwork = modelData;
                root.nState.selectedNetworkUuid = Connectivity.wifi.details[modelData.device.name]?.uuid ?? "";
                root.nState.selectedNetworkSsid = modelData.name;
                root.nState.networkDetailsFromSaved = false;
                root.nState.openSubPage(3);
            }
        }

        Behavior on textOpacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        Connections {
            function onConnectedChanged(): void {
                if (network.modelData.connected)
                    network.currentSelected = false;
            }

            target: network.modelData
        }

        Connections {
            function onNetworkSelected(ap: var): void {
                if (ap !== network.modelData)
                    network.currentSelected = false;
            }

            target: root
        }

        RowLayout {
            id: networkLayout

            anchors.fill: parent
            anchors.margins: CortetsuTokens.padding.large
            anchors.leftMargin: CortetsuTokens.padding.extraLarge
            anchors.rightMargin: CortetsuTokens.padding.extraLarge
            spacing: CortetsuTokens.spacing.medium

            CortetsuIcon {
                text: Icons.getNetworkIcon(Math.round(network.modelData.signalStrength * 100))
                color: network.modelData.connected ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3onSurfaceVariant
                fontStyle: CortetsuTokens.font.icon.medium
                opacity: network.textOpacity
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                opacity: network.textOpacity

                CortetsuText {
                    Layout.fillWidth: true
                    text: network.modelData.name
                    font: CortetsuTokens.font.body.small
                    elide: Text.ElideRight
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Security: %1%2").arg(WifiSecurityType.toString(network.modelData.security)).arg(network.modelData.connected ? qsTr(" • Connected") : network.modelData.known ? qsTr(" • Saved") : "")
                    color: CortetsuColours.palette.m3outline
                    font: CortetsuTokens.font.label.small
                    elide: Text.ElideRight
                }
            }

            AnimLoader {
                sourceComp: Connectivity.wifi.busy && Connectivity.wifi.operationNetwork === network.modelData ? loadingComp : iconComp

                Component {
                    id: iconComp

                    CortetsuIcon {
                        text: network.modelData.connected ? "settings" : "lock"
                        color: network.modelData.connected ? CortetsuColours.palette.m3primary : CortetsuColours.palette.m3onSurfaceVariant
                        fontStyle: CortetsuTokens.font.icon.medium
                        opacity: network.textOpacity
                    }
                }

                Component {
                    id: loadingComp

                    LoadingIndicator {
                        implicitSize: Math.round(CortetsuTokens.font.icon.medium.pointSize * 1.3)
                    }
                }
            }
        }
    }

    StyledProgressBar {
        id: scanningIndicator

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 1
        implicitHeight: Connectivity.wifi.scanning ? CortetsuTokens.rounding.extraSmall : 0
        indeterminate: true

        Behavior on implicitHeight {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }
}
