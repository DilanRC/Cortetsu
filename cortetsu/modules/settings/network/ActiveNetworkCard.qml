pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../CortetsuDesign.js" as CortetsuDesign
import "../../CortetsuTypography.js" as CortetsuTypography

CortetsuSurface {
    id: root

    required property var page

    visible: !!root.page.activeNetwork
    implicitHeight: 104
    baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.64)
    outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.54)
    outlined: true
    radiusValue: CortetsuDesign.radiusMedium

    RowLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        CortetsuSurface {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.18)
            outlined: false
            radiusValue: CortetsuDesign.radiusMedium

            CortetsuIcon {
                anchors.centerIn: parent
                text: "wifi"
                color: CortetsuDesign.colorPrimary
                iconSize: CortetsuTypography.iconLargePx
            }
        }

        ColumnLayout {
            Layout.preferredWidth: 185
            Layout.minimumWidth: 145
            spacing: 2

            CortetsuText {
                text: qsTr("Conexión actual")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            CortetsuText {
                Layout.fillWidth: true
                text: root.page.activeNetwork?.name ?? qsTr("No hay conexión Wi‑Fi activa")
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("%1 · %2 · %3 · %4")
                    .arg(root.page.wifi.connectivity === "full" ? qsTr("Conectada") : root.page.wifi.connectivity === "portal" ? qsTr("Portal cautivo") : root.page.wifi.connectivity === "limited" ? qsTr("Conectividad limitada") : qsTr("Sin Internet"))
                    .arg(root.page.signalLabel(root.page.networkSignal(root.page.activeNetwork)))
                    .arg(root.page.securityLabel(root.page.activeNetwork))
                    .arg(root.page.activeNetwork?.device?.name || qsTr("dispositivo no disponible"))
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
                elide: Text.ElideRight
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 150
            spacing: CortetsuDesign.spacingCompact

            RowLayout {
                Layout.fillWidth: true
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Calidad de la señal")
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
                CortetsuText {
                    text: root.page.signalText(root.page.networkSignal(root.page.activeNetwork))
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                }
            }

            CortetsuProgressBar {
                Layout.fillWidth: true
                value: root.page.signalValue(root.page.networkSignal(root.page.activeNetwork))
                fillColor: CortetsuDesign.colorPrimary
                barHeight: 6
            }

            SignalBars {
                Layout.alignment: Qt.AlignRight
                signalValue: Math.max(0, root.page.networkSignal(root.page.activeNetwork))
                activeColor: CortetsuDesign.colorPrimary
            }
        }

        RowLayout {
            visible: !root.page.compactLayout
            Layout.alignment: Qt.AlignRight
            spacing: CortetsuDesign.spacingCompact

            CortetsuButton {
                compact: true
                danger: true
                icon: "link_off"
                label: qsTr("Desconectar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.page.disconnectActive()
            }

            CortetsuButton {
                compact: true
                icon: "visibility_off"
                label: qsTr("Olvidar")
                disabled: CortetsuSettingsNetwork.busy
                onClicked: root.page.forgetActive()
            }
        }
    }
}
