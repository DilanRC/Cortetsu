pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../../utils"
import "../../../services"
import "../../../components"
import "../../CortetsuDesign.js" as CortetsuDesign
import "../.."

CortetsuPopupSurface {
    id: root

    required property var popouts
    implicitWidth: 336
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property var device: CortetsuNetwork.wifiDevice
    readonly property bool wiredActive: !!CortetsuNetwork.activeEthernet
    property var passwordNetwork: null
    readonly property var networks: (device?.networks?.values ?? []).slice().sort((a, b) => {
        if (a.connected !== b.connected) return b.connected - a.connected;
        return (b.signalStrength ?? 0) - (a.signalStrength ?? 0);
    })
    readonly property var availableNetworks: root.networks.filter(network => !network.connected)

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            title: qsTr("Network")
            detail: CortetsuNetwork.connecting
                ? qsTr("Connecting")
                : root.device
                    ? qsTr("Wi‑Fi ready")
                    : root.wiredActive
                        ? qsTr("Ethernet")
                        : qsTr("Unavailable")
        }

        CortetsuSurface {
            Layout.fillWidth: true
            visible: CortetsuNetwork.active !== null || root.wiredActive
            implicitHeight: 76
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.62)
            outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.3)
            outlined: true

            Row {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                Item {
                    width: 42
                    height: 42
                    anchors.verticalCenter: parent.verticalCenter

                    CortetsuSurface {
                        anchors.fill: parent
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.16)
                    }

                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: CortetsuNetwork.active !== null
                            ? Icons.getNetworkIcon(CortetsuNetwork.active?.strength ?? 0)
                            : "lan"
                        iconSize: CortetsuDesign.iconMediumPx + 4
                        color: CortetsuDesign.colorWashi
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    width: Math.max(0, parent.width - x)

                    CortetsuText {
                        width: parent.width
                        text: CortetsuNetwork.active?.ssid ?? qsTr("Ethernet")
                        textSize: CortetsuDesign.bodyPx
                        font.weight: Font.DemiBold
                        color: CortetsuDesign.colorOnSurface
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        width: parent.width
                        text: CortetsuNetwork.connecting ? qsTr("Connecting…") : qsTr("Connected")
                        textSize: CortetsuDesign.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: CortetsuNetwork.connecting || (!root.device && !root.wiredActive)
                || (root.device && root.networks.length === 0)
            kind: CortetsuNetwork.connecting ? "loading" : !root.device && !root.wiredActive ? "error" : "empty"
            title: CortetsuNetwork.connecting
                ? qsTr("Establishing connection…")
                : !root.device && !root.wiredActive
                    ? qsTr("Network unavailable")
                    : qsTr("No networks available")
            detail: !root.device && !root.wiredActive
                ? qsTr("The network device is not ready")
                : CortetsuNetwork.connecting
                    ? qsTr("Cortetsu will update this surface when the link is ready")
                    : ""
        }

        CortetsuSectionHeader {
            visible: root.device && root.availableNetworks.length > 0
            title: qsTr("Available")
            detail: qsTr("%1 networks").arg(root.availableNetworks.length)
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 5 * CortetsuDesign.rowHeight)
            visible: root.device && root.availableNetworks.length > 0
            clip: true
            spacing: CortetsuDesign.spacingUnit
            model: root.availableNetworks
            delegate: CortetsuListRow {
                required property var modelData
                width: ListView.view.width
                icon: Icons.getNetworkIcon(modelData.signalStrength ?? 0)
                title: modelData.name ?? qsTr("Hidden network")
                subtitle: modelData.security === WifiSecurityType.None
                    ? qsTr("Open network")
                    : modelData.known
                        ? qsTr("Saved · secured")
                        : qsTr("Secured network")
                selected: false
                onClicked: {
                    if (modelData.known || modelData.security === WifiSecurityType.None) {
                        modelData.connect();
                    } else {
                        root.passwordNetwork = modelData;
                        root.popouts.currentName = "wirelesspassword";
                    }
                }
            }
        }
    }
}
