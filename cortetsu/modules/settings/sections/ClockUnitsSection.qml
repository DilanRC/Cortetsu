pragma ComponentBehavior: Bound

import QtQuick
import "../.."
import "../controls"

SettingsGroup {
    title: qsTr("Reloj y unidades")
    icon: "schedule"

    SettingToggleRow {
        objectName: "clockFormat"
        title: qsTr("Reloj de 12 horas")
        detail: CortetsuConfig.useTwelveHourClock ? qsTr("Se muestra como 3:45 p. m.") : qsTr("Se muestra como 15:45")
        checked: CortetsuConfig.useTwelveHourClock
        onToggled: value => { CortetsuConfig.useTwelveHourClock = value; CortetsuConfig.save(); }
    }

    SettingToggleRow {
        objectName: "clockSeconds"
        title: qsTr("Mostrar segundos")
        detail: qsTr("Actualizar el reloj una vez por segundo")
        checked: CortetsuConfig.useSecondPrecision
        onToggled: value => { CortetsuConfig.useSecondPrecision = value; CortetsuConfig.save(); }
    }

    SettingToggleRow {
        objectName: "useFahrenheit"
        title: qsTr("Temperatura en Fahrenheit")
        detail: qsTr("En el clima y en las lecturas del equipo")
        checked: CortetsuConfig.useFahrenheit
        onToggled: value => { CortetsuConfig.useFahrenheit = value; CortetsuConfig.save(); }
    }
}
