pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

// The network chosen in the list, as the page's one protagonist block: what
// it is, how well it is heard, and the three facts worth reading before
// acting on it. Only what NetworkManager reports is shown.
CortetsuHero {
    id: root

    required property var page
    readonly property var network: root.page.selectedNetwork
    readonly property real signal: root.page.networkSignal(root.network)

    objectName: "networkHero"
    Layout.fillWidth: true
    visible: !root.page.showingProfiles && !!root.network

    RowLayout {
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        CortetsuIconBadge {
            Layout.preferredWidth: 52
            Layout.preferredHeight: 52
            icon: root.page.selectedIsActive ? "wifi" : "wifi_find"
            iconSize: CortetsuTypography.iconLargePx
            tone: root.page.selectedIsActive ? CortetsuDesign.colorSuccess : CortetsuDesign.colorIndicator
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            RowLayout {
                spacing: CortetsuDesign.spacingCompact

                CortetsuText {
                    text: root.page.selectedIsActive ? qsTr("Conectada ahora") : qsTr("Red disponible")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }

                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    visible: root.page.selectedIsActive
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: width / 2
                    color: CortetsuDesign.colorSuccess
                }
            }

            CortetsuText {
                objectName: "networkHeroName"
                Layout.fillWidth: true
                text: root.network?.name || qsTr("Red sin nombre")
                textSize: CortetsuTypography.titleLargePx
                font.family: CortetsuDesign.fontHeading
                font.weight: CortetsuDesign.headingWeight
                elide: Text.ElideRight
            }
        }

        CortetsuButton {
            objectName: "copyNetworkPassword"
            visible: root.page.selectedCanCopyPassword
            compact: true
            icon: root.page.secretState === "ready" ? "check" : "key"
            label: root.page.secretState === "ready" ? qsTr("Contraseña copiada") : qsTr("Copiar contraseña")
            tooltipText: qsTr("Queda en el portapapeles 45 segundos")
            disabled: CortetsuSettingsNetwork.secretBusy
            onClicked: root.page.copySelectedPassword()
        }
    }

    CortetsuText {
        width: parent.width
        visible: root.page.selectedCanCopyPassword && CortetsuSettingsNetwork.secretState === "error"
        text: CortetsuSettingsNetwork.secretError
        textSize: CortetsuTypography.labelSmallPx
        color: CortetsuDesign.colorWarning
        wrapMode: Text.WordWrap
    }

    CortetsuDivider {
        width: parent.width
    }

    RowLayout {
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        SignalBars {
            Layout.alignment: Qt.AlignVCenter
            signalValue: Math.max(0, root.signal)
            activeColor: root.page.selectedIsActive ? CortetsuDesign.colorSuccess : CortetsuDesign.colorIndicator
        }

        CortetsuFact {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            label: qsTr("Señal")
            value: root.signal >= 0
                ? qsTr("%1 · %2").arg(root.page.signalText(root.signal)).arg(root.page.signalLabel(root.signal))
                : qsTr("Sin medición")
        }

        CortetsuFact {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            icon: root.network && root.page.securityLabel(root.network) === qsTr("Red abierta") ? "lock_open" : "lock"
            label: qsTr("Seguridad")
            value: root.page.securityLabel(root.network)
        }

        CortetsuFact {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            icon: "router"
            label: qsTr("Dispositivo")
            value: root.page.detailsValue(root.network?.device?.name)
        }
    }
}
