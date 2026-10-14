pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    readonly property bool calibrating: DisplayCalibration.state === "applying"

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Brillo")
        detail: root.context.screen?.name ?? ""

        SettingSliderRow {
            objectName: "brightness"
            visible: root.context.brightnessValue >= 0
            title: qsTr("Brillo de esta pantalla")
            valueText: qsTr("%1 %").arg(Math.round(root.context.brightnessValue * 100))
            value: root.context.brightnessValue
            onMoved: next => root.context.brightnessMonitor?.setBrightness(next)
        }

        SettingValueRow {
            objectName: "brightnessUnavailable"
            visible: root.context.brightnessValue < 0
            title: qsTr("Brillo de esta pantalla")
            detail: qsTr("Esta pantalla no ofrece control de brillo al sistema")
            value: qsTr("No disponible")
        }
    }

    SettingsGroup {
        title: qsTr("Color")
        detail: qsTr("Filtro aplicado por hyprsunset a todas las pantallas")

        SettingToggleRow {
            objectName: "colourFilter"
            title: qsTr("Filtro de color")
            detail: CortetsuConfig.colorCalibrationEnabled
                ? qsTr("Activo: %1 K, gamma %2 %").arg(CortetsuConfig.colorTemperature).arg(CortetsuConfig.colorGamma)
                : qsTr("Apagado: colores nativos de la pantalla")
            checked: CortetsuConfig.colorCalibrationEnabled
            status: root.calibrating ? "busy" : DisplayCalibration.state === "failed" ? "error" : ""
            statusText: root.calibrating ? qsTr("Aplicando…") : DisplayCalibration.error
            onToggled: value => DisplayCalibration.setEnabled(value)
        }

        SettingSliderRow {
            title: qsTr("Temperatura de color")
            valueText: qsTr("%1 K").arg(CortetsuConfig.colorTemperature)
            from: 2500
            to: 6500
            step: 100
            value: CortetsuConfig.colorTemperature
            disabled: !CortetsuConfig.colorCalibrationEnabled
            onMoved: next => DisplayCalibration.setTemperature(next)
        }

        SettingSliderRow {
            title: qsTr("Gamma")
            valueText: qsTr("%1 %").arg(CortetsuConfig.colorGamma)
            from: 50
            to: 150
            step: 1
            value: CortetsuConfig.colorGamma
            disabled: !CortetsuConfig.colorCalibrationEnabled
            onMoved: next => DisplayCalibration.setGamma(next)
        }

        SettingSliderRow {
            visible: Nvibrant.available
            title: qsTr("Vibrance NVIDIA · %1").arg(Nvibrant.connector)
            valueText: Nvibrant.requested !== Nvibrant.value || !Nvibrant.known
                ? (Nvibrant.busy ? qsTr("Aplicando %1").arg(Nvibrant.requested) : qsTr("Sin confirmar"))
                : String(Nvibrant.value)
            from: Nvibrant.minimum
            to: Nvibrant.maximum
            step: 1
            value: Nvibrant.requested
            status: Nvibrant.error.length > 0 ? "error" : ""
            statusText: Nvibrant.error
            onMoved: next => Nvibrant.setValue(next)
        }
    }

    SettingsGroup {
        title: qsTr("Monitores")
        detail: root.context.monitorCount === 1 ? qsTr("1 detectado") : qsTr("%1 detectados").arg(root.context.monitorCount)

        Repeater {
            model: ScriptModel { values: [...(Hypr.monitors?.values ?? [])] }

            delegate: SettingValueRow {
                required property var modelData
                title: modelData.name ?? qsTr("Monitor")
                detail: (modelData.focused ?? modelData.active) === true ? qsTr("Pantalla enfocada") : ""
                value: modelData.width && modelData.height
                    ? qsTr("%1 × %2 · escala %3").arg(modelData.width).arg(modelData.height).arg(modelData.scale ?? 1)
                    : qsTr("Modo no disponible")
            }
        }

        SettingActionRow {
            title: qsTr("Resolución, posición y escala")
            detail: qsTr("Se organizan en el gestor de pantallas, con vista previa")
            actionLabel: qsTr("Abrir gestor")
            actionIcon: "monitor"
            onActivated: root.context.openSurface("displayManager")
        }
    }
}
