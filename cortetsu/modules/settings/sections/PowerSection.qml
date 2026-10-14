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
            objectName: "keepAwake"
            title: qsTr("Mantener despierto")
            detail: CortetsuIdleInhibitor.enabled
                ? qsTr("Sin bloqueo, apagado ni suspensión por inactividad; Suspender sigue funcionando")
                : qsTr("Desactivado · también con SUPER+ALT+K o desde la barra inferior")
            checked: CortetsuIdleInhibitor.enabled
            onToggled: value => CortetsuIdleInhibitor.enabled = value
        }

        Repeater {
            model: [
                { action: "lock", name: "idleLock", title: qsTr("Bloquear tras inactividad"), to: 60, step: 1 },
                { action: "dpms", name: "idleScreenOff", title: qsTr("Apagar la pantalla tras inactividad"), to: 60, step: 1 },
                { action: "suspend", name: "idleSuspend", title: qsTr("Suspender tras inactividad"), to: 120, step: 5 }
            ]

            delegate: SettingSliderRow {
                id: idleRow
                required property var modelData
                readonly property int minutes: CortetsuConfig.idleMinutes(modelData.action)
                // Suspend that logind refuses is shown, with the reason, but cannot be set.
                readonly property string refusal: modelData.action === "suspend" ? CortetsuSession.reason("suspend") : ""

                objectName: modelData.name
                title: modelData.title
                valueText: refusal || (minutes > 0 ? qsTr("%1 min").arg(minutes) : qsTr("Nunca"))
                disabled: refusal.length > 0
                from: 0
                to: Math.max(modelData.to, minutes)
                step: modelData.step
                value: minutes
                onMoved: next => {
                    CortetsuConfig.setIdleMinutes(modelData.action, Math.round(next));
                    CortetsuConfig.save();
                }
            }
        }

        SettingToggleRow {
            title: qsTr("Suspender por inactividad solo con batería")
            detail: qsTr("Nunca con una pantalla externa conectada")
            checked: CortetsuConfig.idleSuspendOnBatteryOnly
            onToggled: value => { CortetsuConfig.idleSuspendOnBatteryOnly = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Evitar reposo en pantalla completa")
            detail: qsTr("No apaga la pantalla ni suspende; el bloqueo sigue activo")
            checked: CortetsuConfig.idleInhibitWhenFullscreen
            onToggled: value => { CortetsuConfig.idleInhibitWhenFullscreen = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Evitar reposo durante el audio")
            detail: qsTr("No apaga la pantalla ni suspende mientras algo suena; el bloqueo sigue activo")
            checked: CortetsuConfig.idleInhibitWhenAudio
            onToggled: value => { CortetsuConfig.idleInhibitWhenAudio = value; CortetsuConfig.save(); }
        }

        SettingToggleRow {
            title: qsTr("Evitar reposo mientras carga")
            detail: qsTr("No apaga la pantalla ni suspende enchufado; el bloqueo sigue activo")
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
