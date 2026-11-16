pragma ComponentBehavior: Bound

import QtQuick
import "../../../services"
import "../.."
import "../controls"

// Brightness, saturation and the colour filter of Settings → Pantalla. They
// apply at once, without the preview flow. Saturation works on any output
// through the screen shader; NVIDIA outputs also offer Digital Vibrance.
    SettingsGroup {
    id: root
    objectName: "displayColour"
    required property var context
    // The output selected in the arrangement and what the probe knows of it.
    required property var selected
    required property var live
    readonly property bool saturation: DisplayVibrance.hasOutput(selected?.name ?? "")
    readonly property int saturationValue: DisplayVibrance.valueFor(selected?.name ?? "")
    readonly property bool vibrance: Nvibrant.available && Nvibrant.connector === (selected?.name ?? "")
    readonly property bool calibrating: DisplayCalibration.state === "applying"
    property string scheduleError: ""

    function holdText(): string {
        if (!DisplayCalibration.held)
            return "";
        return qsTr(" · cambio manual hasta las %1").arg(Qt.formatTime(new Date(DisplayCalibration.holdUntil), "HH:mm"));
    }

    function commitTime(which: string, value: string): void {
        const clock = value.trim();
        if (!CortetsuConfig.validClock(clock)) {
            root.scheduleError = qsTr("Usa el formato 24 h, por ejemplo 20:00");
            return;
        }
        root.scheduleError = "";
        if (which === "from")
            DisplayCalibration.setScheduleTimes(clock, CortetsuConfig.nightLightTo);
        else
            DisplayCalibration.setScheduleTimes(CortetsuConfig.nightLightFrom, clock);
    }

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

    SettingSliderRow {
        objectName: "displaySaturation"
        visible: root.saturation
        title: qsTr("Saturación · %1").arg(root.selected?.name ?? "")
        valueText: DisplayVibrance.busy ? qsTr("Aplicando %1").arg(root.saturationValue) : String(root.saturationValue)
        from: DisplayVibrance.minimum
        to: DisplayVibrance.maximum
        step: 1
        value: root.saturationValue
        status: DisplayVibrance.error.length > 0 || !DisplayVibrance.active ? "error" : ""
        statusText: DisplayVibrance.error
            || qsTr("Hyprland usa otro shader de pantalla; mover el control lo sustituye por el de Cortetsu")
        onMoved: next => DisplayVibrance.setValue(root.selected?.name ?? "", next)
    }

    SettingValueRow {
        objectName: "displaySaturationUnavailable"
        visible: !!root.selected && !root.saturation
        title: qsTr("Saturación")
        detail: qsTr("Hyprland no tiene esta salida activa")
        value: qsTr("No disponible")
    }

    // nVibrant drives NVIDIA's Digital Vibrance in the driver, on top of the
    // shader saturation above.
    SettingSliderRow {
        objectName: "displayVibrance"
        visible: root.vibrance
        title: qsTr("Digital Vibrance (NVIDIA) · %1").arg(Nvibrant.connector)
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

    SettingToggleRow {
        objectName: "colourFilter"
        title: qsTr("Filtro de color")
        detail: (CortetsuConfig.colorCalibrationEnabled
            ? qsTr("Activo en todas las pantallas: %1 K, gamma %2 %").arg(CortetsuConfig.colorTemperature).arg(CortetsuConfig.colorGamma)
            : qsTr("Apagado: colores nativos (hyprsunset, todas las pantallas)")) + root.holdText()
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

    // Night light: the same filter, switched by the clock.
    SettingToggleRow {
        objectName: "nightLightSchedule"
        title: qsTr("Luz nocturna programada")
        detail: CortetsuConfig.nightLightSchedule
            ? qsTr("El filtro se enciende de %1 a %2").arg(CortetsuConfig.nightLightFrom).arg(CortetsuConfig.nightLightTo)
            : qsTr("Enciende y apaga el filtro de color a una hora fija")
        checked: CortetsuConfig.nightLightSchedule
        onToggled: value => DisplayCalibration.setSchedule(value)
    }

    SettingTextRow {
        objectName: "nightLightFrom"
        visible: CortetsuConfig.nightLightSchedule
        title: qsTr("Encender a las")
        value: CortetsuConfig.nightLightFrom
        placeholderText: "20:00"
        status: root.scheduleError ? "error" : ""
        statusText: root.scheduleError
        onCommitted: value => root.commitTime("from", value)
    }

    SettingTextRow {
        objectName: "nightLightTo"
        visible: CortetsuConfig.nightLightSchedule
        title: qsTr("Apagar a las")
        value: CortetsuConfig.nightLightTo
        placeholderText: "07:00"
        onCommitted: value => root.commitTime("to", value)
    }
}
