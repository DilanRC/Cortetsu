pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../controls"

SettingsGroup {
    title: qsTr("Visualizador de audio")
    icon: "graphic_eq"
    detail: qsTr("Barras sobre el fondo mientras suena algo")

    SettingToggleRow {
        objectName: "visualiserEnabled"
        title: qsTr("Visualizador de audio")
        checked: CortetsuConfig.visualiserEnabled
        onToggled: value => { CortetsuConfig.visualiserEnabled = value; CortetsuConfig.save(); }
    }

    SettingToggleRow {
        title: qsTr("Solo con ventanas flotantes")
        detail: qsTr("Ocultarlo cuando el espacio no tiene ventanas flotantes")
        checked: CortetsuConfig.visualiserAutoHide
        disabled: !CortetsuConfig.visualiserEnabled
        onToggled: value => { CortetsuConfig.visualiserAutoHide = value; CortetsuConfig.save(); }
    }

    SettingSliderRow {
        title: qsTr("Número de barras")
        valueText: String(CortetsuConfig.visualiserBars)
        from: 8
        to: 128
        step: 4
        value: CortetsuConfig.visualiserBars
        disabled: !CortetsuConfig.visualiserEnabled
        onMoved: next => { CortetsuConfig.visualiserBars = Math.round(next / 4) * 4; CortetsuConfig.save(); }
    }
}
