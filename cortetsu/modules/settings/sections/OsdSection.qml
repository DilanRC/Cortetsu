pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../controls"

SettingsGroup {
    title: qsTr("Indicadores de volumen y brillo")
    icon: "tune"
    detail: qsTr("El indicador compacto se oculta 0,2 s antes; cada pulsación reinicia el tiempo")

    SettingSliderRow {
        objectName: "osdTimeout"
        title: qsTr("Duración del OSD")
        from: 500
        to: 5000
        step: 100
        value: CortetsuConfig.osdTimeoutMs
        valueText: qsTr("%1 s").arg((value / 1000).toFixed(1))
        onMoved: next => { CortetsuConfig.osdTimeoutMs = Math.round(next); }
    }
}
