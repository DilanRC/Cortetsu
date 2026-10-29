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
            onToggled: value => CortetsuNotifications.setDnd(value)
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

        SettingToggleRow {
            title: qsTr("Avisar del modo de juego")
            detail: qsTr("Un aviso breve al entrar o salir del modo de juego")
            checked: CortetsuConfig.toastGameModeChanged
            onToggled: value => { CortetsuConfig.toastGameModeChanged = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar de Bloq Mayús")
            detail: qsTr("Un aviso breve al activar o desactivar Bloq Mayús")
            checked: CortetsuConfig.toastCapsLockChanged
            onToggled: value => { CortetsuConfig.toastCapsLockChanged = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar de Bloq Num")
            detail: qsTr("Un aviso breve al activar o desactivar Bloq Num")
            checked: CortetsuConfig.toastNumLockChanged
            onToggled: value => { CortetsuConfig.toastNumLockChanged = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar del cambio de distribución")
            detail: qsTr("Un aviso breve al cambiar la distribución del teclado")
            checked: CortetsuConfig.toastKbLayoutChanged
            onToggled: value => { CortetsuConfig.toastKbLayoutChanged = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar de No molestar")
            detail: qsTr("Un aviso breve al activar o desactivar No molestar")
            checked: CortetsuConfig.toastDndChanged
            onToggled: value => { CortetsuConfig.toastDndChanged = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Avisar de la pista en reproducción")
            detail: qsTr("Un aviso al cambiar de pista o de reproductor")
            checked: CortetsuConfig.toastNowPlaying
            onToggled: value => { CortetsuConfig.toastNowPlaying = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Abrir avisos expandidos")
            detail: qsTr("Mostrar el cuerpo completo de cada aviso al llegar")
            checked: CortetsuConfig.notificationOpenExpanded
            onToggled: value => { CortetsuConfig.notificationOpenExpanded = value; CortetsuConfig.save(); }
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
