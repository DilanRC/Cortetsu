pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../theme"
import "../.."
import ".."
import "../controls"

ColumnLayout {
    id: root
    required property var context
    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Movimiento")
        icon: "animation"

        SettingToggleRow {
            objectName: "reducedMotion"
            title: qsTr("Reducir movimiento")
            detail: qsTr("Los cambios de la interfaz ocurren sin animación")
            checked: CortetsuConfig.reducedMotion
            onToggled: value => { CortetsuConfig.reducedMotion = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Visibilidad")
        icon: "contrast"
        detail: qsTr("Los textos de cada tema y esquema se ajustan para alcanzar contraste AA")

        SettingSliderRow {
            objectName: "borderThickness"
            title: qsTr("Grosor de bordes")
            valueText: qsTr("%1 px").arg(CortetsuConfig.borderThickness)
            from: 0
            to: 8
            step: 1
            value: CortetsuConfig.borderThickness
            onMoved: next => { CortetsuConfig.borderThickness = Math.round(next); CortetsuConfig.save(); }
        }

        SettingNavRow {
            title: qsTr("Superficies transparentes")
            detail: qsTr("Desactívalas en Temas para ganar contraste sobre fondos cargados")
            icon: "opacity"
            value: CortetsuConfig.transparencyEnabled ? qsTr("Activadas") : qsTr("Desactivadas")
            onActivated: SettingsController.openResult("themes", qsTr("Superficies transparentes"))
        }
    }
}
