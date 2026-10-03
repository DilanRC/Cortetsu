pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../services"
import ".."
import "../../../theme"
import "../../CortetsuTypography.js" as CortetsuTypography

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Pantalla")
        detail: qsTr("Brillo y distribución de la pantalla actual")
    }

    DomainHero {
        icon: "monitor"
        title: root.page.brightnessValue < 0 ? qsTr("Brillo no disponible") : qsTr("Pantalla activa")
        detail: root.page.screen?.name ?? qsTr("Monitor actual")
        value: root.page.brightnessValue < 0
            ? qsTr("Sin lectura")
            : qsTr("%1% de brillo").arg(Math.round(root.page.brightnessValue * 100))
        meta: qsTr("%1 monitores detectados").arg(root.page.monitorCount)
        progress: root.page.brightnessValue
        warningState: root.page.brightnessValue < 0
    }

    CortetsuSurface {
        Layout.fillWidth: true
        implicitHeight: 92
        radiusValue: CortetsuDesign.radiusMedium
        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.72)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingStandard
            spacing: CortetsuDesign.spacingCompact
            RowLayout {
                Layout.fillWidth: true
                CortetsuIcon {
                    text: "brightness_6"
                    iconSize: CortetsuTypography.iconSmallPx
                    color: root.page.brightnessValue < 0 ? CortetsuDesign.colorOnSurfaceVariant : CortetsuDesign.colorPrimary
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: qsTr("Brillo")
                    textSize: CortetsuTypography.bodyPx
                    font.weight: Font.DemiBold
                }
                CortetsuText {
                    text: root.page.brightnessValue < 0
                        ? qsTr("No disponible")
                        : qsTr("%1%").arg(Math.round(root.page.brightnessValue * 100))
                    textSize: CortetsuTypography.labelSmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                }
            }
            CortetsuSlider {
                Layout.fillWidth: true
                value: root.page.brightnessValue
                disabled: value < 0
                onMoved: nextValue => root.page.brightnessMonitor?.setBrightness(nextValue)
            }
        }
    }

    DisplayCalibration {
        Layout.fillWidth: true
    }

    ActionCard {
        title: qsTr("Abrir gestor de pantallas")
        detail: qsTr("Organizar monitores, modos y opciones de cada pantalla")
        icon: "monitor"
        onActivated: root.page.openRetained("displayManager")
    }

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Monitores detectados")
        detail: qsTr("Lectura actual de Hyprland; los modos se editan en el gestor")
    }

    Repeater {
        model: Hypr.monitors?.values ?? []
        delegate: StatusCard {
            required property var modelData
            title: modelData.name ?? qsTr("Monitor")
            value: modelData.active ? qsTr("Enfocado") : qsTr("Disponible")
            detail: modelData.width && modelData.height
                ? qsTr("%1 × %2 · escala %3").arg(modelData.width).arg(modelData.height).arg(modelData.scale ?? 1)
                : qsTr("Modo administrado por Hyprland")
            icon: modelData.active ? "monitor" : "desktop_windows"
            activeState: modelData.active === true
        }
    }
}
