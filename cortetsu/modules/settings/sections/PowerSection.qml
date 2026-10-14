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
        title: qsTr("Batería")
        visible: CortetsuPower.hasBattery

        SettingValueRow {
            objectName: "batteryLevel"
            title: qsTr("Carga")
            value: qsTr("%1 %").arg(CortetsuPower.percent)
            attention: CortetsuPower.critical
        }

        SettingValueRow {
            title: qsTr("Fuente")
            value: CortetsuPower.onBattery ? qsTr("Batería") : qsTr("Corriente")
        }

        SettingValueRow {
            title: CortetsuPower.charging ? qsTr("Carga completa en") : qsTr("Autonomía estimada")
            value: root.context.formatDuration(CortetsuPower.charging ? CortetsuPower.timeToFull : CortetsuPower.timeToEmpty)
        }
    }

    SettingsGroup {
        title: qsTr("Alimentación")
        visible: !CortetsuPower.hasBattery

        SettingValueRow {
            objectName: "noBattery"
            title: qsTr("Fuente")
            detail: qsTr("Este equipo no informa de una batería")
            value: qsTr("Corriente")
        }
    }

    SettingsGroup {
        title: qsTr("Reposo")
        detail: qsTr("Cuándo se mantiene despierta la sesión")

        SettingToggleRow {
            title: qsTr("Evitar reposo durante el audio")
            detail: qsTr("No suspender mientras algo se reproduce")
            checked: CortetsuConfig.idleInhibitWhenAudio
            onToggled: value => { CortetsuConfig.idleInhibitWhenAudio = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Evitar reposo mientras carga")
            detail: qsTr("No suspender con el equipo enchufado")
            checked: CortetsuConfig.idleInhibitWhenCharging
            onToggled: value => { CortetsuConfig.idleInhibitWhenCharging = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Bloquear antes de suspender")
            detail: qsTr("Pedir la contraseña al volver de la suspensión")
            checked: CortetsuConfig.idleLockBeforeSleep
            onToggled: value => { CortetsuConfig.idleLockBeforeSleep = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Perfiles de energía")

        SettingActionRow {
            title: qsTr("Perfil, límites y automatización")
            detail: qsTr("Se ajustan en Hardware, página Energía")
            actionLabel: qsTr("Abrir Hardware")
            actionIcon: "memory"
            onActivated: root.context.openSurface("hardware")
        }
    }
}
