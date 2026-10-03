pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Interrupciones")

        SettingToggleRow {
            objectName: "dnd"
            title: qsTr("No molestar")
            detail: CortetsuNotifications.dnd
                ? qsTr("Los avisos se guardan en el historial sin aparecer en pantalla")
                : qsTr("Los avisos aparecen en pantalla al llegar")
            checked: CortetsuNotifications.dnd
            onToggled: value => CortetsuNotifications.dnd = value
        }

        SettingToggleRow {
            title: qsTr("Ocultar en pantalla completa")
            detail: qsTr("No mostrar avisos sobre una ventana a pantalla completa")
            checked: CortetsuConfig.suppressNotificationsInFullscreen
            onToggled: value => { CortetsuConfig.suppressNotificationsInFullscreen = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Avisos")

        SettingSliderRow {
            title: qsTr("Avisos visibles por grupo")
            valueText: String(CortetsuConfig.notificationGroupPreviewNum)
            from: 1
            to: 6
            step: 1
            value: CortetsuConfig.notificationGroupPreviewNum
            onMoved: next => { CortetsuConfig.notificationGroupPreviewNum = Math.round(next); CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar del modo de juego")
            detail: qsTr("Un aviso breve al entrar o salir del modo de juego")
            checked: CortetsuConfig.toastGameModeChanged
            onToggled: value => { CortetsuConfig.toastGameModeChanged = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Historial")

        SettingActionRow {
            objectName: "clearHistory"
            title: CortetsuNotifications.count === 0
                ? qsTr("El historial está vacío")
                : CortetsuNotifications.count === 1
                    ? qsTr("1 notificación guardada")
                    : qsTr("%1 notificaciones guardadas").arg(CortetsuNotifications.count)
            detail: qsTr("Vaciarlo no cambia No molestar")
            actionLabel: qsTr("Vaciar")
            actionIcon: "delete_sweep"
            confirm: true
            disabled: CortetsuNotifications.count === 0
            onActivated: CortetsuNotifications.clear()
        }
    }
}
