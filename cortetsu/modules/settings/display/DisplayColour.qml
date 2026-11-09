pragma ComponentBehavior: Bound

import QtQuick
import "../../../services"
import "../.."
import "../controls"

// Brightness, saturation and the colour filter of Settings → Pantalla. They
// apply at once, without the preview flow. Saturation follows the GPU that
// drives the selected output: nVibrant on NVIDIA, unavailable elsewhere.
    SettingsGroup {
    id: root
    objectName: "displayColour"
    required property var context
    // The output selected in the arrangement and what the probe knows of it.
    required property var selected
    required property var live
    readonly property bool nvidiaOutput: String(live?.gpu_vendor ?? "").toUpperCase() === "NVIDIA"
    readonly property bool vibrance: Nvibrant.available && Nvibrant.connector === (selected?.name ?? "")
    readonly property bool calibrating: DisplayCalibration.state === "applying"

    title: qsTr("Brillo y color")
    icon: "brightness_6"
    detail: qsTr("Se aplican al momento, sin vista previa")

    SettingSliderRow {
        objectName: "brightness"
        visible: root.context.brightnessValue >= 0
        title: root.context.screen?.name ? qsTr("Brillo · %1").arg(root.context.screen.name) : qsTr("Brillo")
        valueText: qsTr("%1 %").arg(Math.round(root.context.brightnessValue * 100))
        value: root.context.brightnessValue
        onMoved: next => root.context.brightnessMonitor?.setBrightness(next)
    }

    SettingValueRow {
        objectName: "brightnessUnavailable"
        visible: root.context.brightnessValue < 0
        title: root.context.screen?.name ? qsTr("Brillo · %1").arg(root.context.screen.name) : qsTr("Brillo")
        detail: qsTr("Esta pantalla no ofrece control de brillo al sistema")
        value: qsTr("No disponible")
    }

    // nVibrant drives NVIDIA's Digital Vibrance on the selected output.
    SettingSliderRow {
        objectName: "displayVibrance"
        visible: root.vibrance
        title: qsTr("Saturación (NVIDIA) · %1").arg(Nvibrant.connector)
        valueText: Nvibrant.busy ? qsTr("Aplicando %1").arg(Nvibrant.requested)
            : Nvibrant.known && Nvibrant.requested === Nvibrant.value ? qsTr("%1 · confirmado").arg(Nvibrant.value)
            : Nvibrant.desiredKnown ? qsTr("%1 guardado · sin confirmar en este arranque").arg(Nvibrant.desired)
            : qsTr("Sin confirmar")
        from: Nvibrant.minimum
        to: Nvibrant.maximum
        step: 1
        value: Nvibrant.requested
        status: Nvibrant.error.length > 0 ? "error" : ""
        statusText: Nvibrant.error
        onMoved: next => Nvibrant.setValue(next)
    }

    SettingValueRow {
        objectName: "displayVibranceUnsupported"
        visible: !!root.selected && !root.vibrance
        title: qsTr("Saturación")
        detail: root.nvidiaOutput
            ? qsTr("nVibrant no encuentra esta salida NVIDIA conectada")
            : qsTr("Solo las salidas de la GPU NVIDIA la admiten (nVibrant). Esta la controla %1.").arg(root.live?.gpu_vendor ?? qsTr("otra GPU"))
        value: qsTr("No compatible")
    }

    SettingToggleRow {
        objectName: "colourFilter"
        title: qsTr("Filtro de color")
        detail: CortetsuConfig.colorCalibrationEnabled
            ? qsTr("Activo en todas las pantallas: %1 K, gamma %2 %").arg(CortetsuConfig.colorTemperature).arg(CortetsuConfig.colorGamma)
            : qsTr("Apagado: colores nativos (hyprsunset, todas las pantallas)")
        checked: CortetsuConfig.colorCalibrationEnabled
        status: root.calibrating ? "busy" : DisplayCalibration.state === "failed" ? "error" : ""
        statusText: root.calibrating ? qsTr("Aplicando…") : DisplayCalibration.error
        onToggled: value => DisplayCalibration.setEnabled(value)
    }

    SettingSliderRow {
        visible: CortetsuConfig.colorCalibrationEnabled
        title: qsTr("Temperatura de color")
        valueText: qsTr("%1 K").arg(CortetsuConfig.colorTemperature)
        from: 2500
        to: 6500
        step: 100
        value: CortetsuConfig.colorTemperature
        onMoved: next => DisplayCalibration.setTemperature(next)
    }

    SettingSliderRow {
        visible: CortetsuConfig.colorCalibrationEnabled
        title: qsTr("Gamma")
        valueText: qsTr("%1 %").arg(CortetsuConfig.colorGamma)
        from: 50
        to: 150
        step: 1
        value: CortetsuConfig.colorGamma
        onMoved: next => DisplayCalibration.setGamma(next)
    }
}
