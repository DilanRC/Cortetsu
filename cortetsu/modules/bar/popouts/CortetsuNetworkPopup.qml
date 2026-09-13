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
    readonly property bool refreshing: CortetsuNetwork.refreshing
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

        RowLayout {
            Layout.fillWidth: true

            CortetsuSectionHeader {
                Layout.fillWidth: true
                title: qsTr("Red")
                detail: CortetsuNetwork.connecting
                    ? qsTr("Conectando")
                    : root.device
                        ? qsTr("Wi‑Fi listo")
                        : root.wiredActive
                            ? qsTr("Ethernet")
                            : qsTr("No disponible")
            }

            CortetsuButton {
                compact: true
                icon: root.refreshing ? "sync" : "refresh"
                label: ""
                tooltipText: qsTr("Actualizar redes")
                disabled: !root.device || root.refreshing
                onClicked: CortetsuNetwork.refresh()
            }
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
                        text: CortetsuNetwork.connecting ? qsTr("Conectando…") : qsTr("Conectado")
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
                ? qsTr("Estableciendo conexión…")
                : !root.device && !root.wiredActive
                    ? qsTr("Red no disponible")
                    : qsTr("No hay redes disponibles")
            detail: !root.device && !root.wiredActive
                ? qsTr("El dispositivo de red no está listo")
                : CortetsuNetwork.connecting
                    ? qsTr("Cortetsu actualizará esta ventana cuando el enlace esté listo")
                    : ""
        }

        CortetsuSectionHeader {
            visible: root.device && root.availableNetworks.length > 0
            title: qsTr("Disponibles")
            detail: qsTr("%1 redes").arg(root.availableNetworks.length)
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
                title: modelData.name ?? qsTr("Red oculta")
                subtitle: modelData.security === WifiSecurityType.None
                    ? qsTr("Red abierta")
                    : modelData.known
                        ? qsTr("Guardada · protegida")
                        : qsTr("Red protegida")
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
