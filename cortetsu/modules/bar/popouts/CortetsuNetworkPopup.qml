pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import "../../../utils"
import "../../../services"
import "../../../components"
import "../../../theme"
import "../.."

CortetsuPopupSurface {
    id: root

    required property var popouts
    implicitWidth: 336
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property var device: CortetsuNetwork.wifiDevice
    readonly property bool refreshing: CortetsuNetwork.refreshing
    readonly property bool wiredActive: !!CortetsuNetwork.activeEthernet
    readonly property string scanOwner: "popup-wifi-" + String(root)
    onVisibleChanged: Connectivity.wifi.setScanOwner(scanOwner, visible)
    Component.onCompleted: Connectivity.wifi.setScanOwner(scanOwner, visible)
    Component.onDestruction: Connectivity.wifi.setScanOwner(scanOwner, false)
    property var passwordNetwork: null
    readonly property var networks: (device?.networks?.values ?? []).slice().sort((a, b) => {
        if (a.connected !== b.connected) return b.connected - a.connected;
        return CortetsuNetwork.strengthPercent(b.signalStrength)
            - CortetsuNetwork.strengthPercent(a.signalStrength);
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
                        text: CortetsuNetwork.connecting ? qsTr("Conectando…") : Connectivity.internetLabel
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
                icon: Icons.getNetworkIcon(CortetsuNetwork.strengthPercent(modelData.signalStrength))
                title: modelData.name ?? qsTr("Red oculta")
                subtitle: Connectivity.wifi.operationNetwork === modelData && ["failed", "auth-required"].includes(Connectivity.wifi.operation.state)
                    ? Connectivity.wifi.operation.lastError
                    : modelData.stateChanging ? qsTr("Conectando…")
                    : modelData.security === WifiSecurityType.Open
                    ? qsTr("Red abierta")
                    : modelData.known
                        ? qsTr("Guardada · protegida")
                        : qsTr("Red protegida")
                selected: false
                onClicked: {
                    if ((modelData.known || modelData.security === WifiSecurityType.Open)
                        && !(Connectivity.wifi.operationNetwork === modelData && Connectivity.wifi.operation.state === "auth-required")) {
                        Connectivity.wifi.connectNetwork(modelData, "", null);
                    } else {
                        root.passwordNetwork = modelData;
                        root.popouts.currentName = "wirelesspassword";
                    }
                }
            }
        }
    }
}
