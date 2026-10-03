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

    visible: !root.page.showingProfiles && !!root.page.selectedNetwork
    implicitHeight: 206
    baseColor: "transparent"
    outlined: false
    radiusValue: 0

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingStandard

        RowLayout {
            Layout.fillWidth: true

            CortetsuSurface {
                Layout.preferredWidth: 54
                Layout.preferredHeight: 54
                baseColor: root.page.selectedIsActive
                    ? Qt.alpha(CortetsuDesign.colorSuccess, 0.16)
                    : Qt.alpha(CortetsuDesign.colorPrimary, 0.14)
                outlined: false
                radiusValue: CortetsuDesign.radiusMedium

                CortetsuIcon {
                    anchors.centerIn: parent
                    text: root.page.selectedIsActive ? "wifi" : "wifi_find"
                    color: root.page.selectedIsActive
                        ? CortetsuDesign.colorSuccess
                        : CortetsuDesign.colorPrimary
                    iconSize: CortetsuTypography.iconLargePx
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    spacing: CortetsuDesign.spacingCompact
                    CortetsuText {
                        text: root.page.selectedIsActive
                            ? qsTr("Conectada ahora")
                            : qsTr("Red disponible")
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                    Rectangle {
                        visible: root.page.selectedIsActive
                        width: 8
                        height: width
                        radius: width / 2
                        color: CortetsuDesign.colorSuccess
                        Layout.alignment: Qt.AlignVCenter
                    }
                }

                CortetsuText {
                    text: root.page.selectedNetwork?.name ?? ""
                    textSize: CortetsuTypography.titleMediumPx
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                CortetsuText {
                    text: root.page.signalLabel(root.page.networkSignal(root.page.selectedNetwork))
                    textSize: CortetsuTypography.bodySmallPx
                    color: root.page.selectedIsActive
                        ? CortetsuDesign.colorSuccess
                        : CortetsuDesign.colorOnSurfaceVariant
                }
            }

            CortetsuText {
                text: root.page.signalText(root.page.networkSignal(root.page.selectedNetwork))
                textSize: CortetsuTypography.titleMediumPx
                font.weight: Font.DemiBold
            }

            CortetsuButton {
                visible: root.page.selectedCanCopyPassword
                compact: true
                icon: root.page.secretState === "ready" ? "check" : "key"
                label: root.page.secretState === "ready"
                    ? qsTr("Contraseña copiada")
                    : qsTr("Copiar contraseña")
                disabled: CortetsuSettingsNetwork.secretBusy
                onClicked: root.page.copySelectedPassword()
            }
        }

        RowLayout {
            Layout.fillWidth: true

            CortetsuText {
                Layout.fillWidth: true
                text: qsTr("Calidad de la señal")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }

            SignalBars {
                signalValue: Math.max(0, root.page.networkSignal(root.page.selectedNetwork))
                activeColor: root.page.selectedIsActive
                    ? CortetsuDesign.colorSuccess
                    : CortetsuDesign.colorPrimary
            }
        }

        CortetsuProgressBar {
            Layout.fillWidth: true
            value: root.page.signalValue(root.page.networkSignal(root.page.selectedNetwork))
            fillColor: root.page.selectedIsActive
                ? CortetsuDesign.colorSuccess
                : CortetsuDesign.colorPrimary
            barHeight: 7
        }
    }
}
