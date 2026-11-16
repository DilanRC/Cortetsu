pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    spacing: CortetsuDesign.spacingSection

    // What the machine runs on comes first; the warning level belongs to
    // the battery and only exists with one.
    SettingsGroup {
        title: CortetsuPower.hasBattery ? qsTr("Batería") : qsTr("Alimentación")
        icon: CortetsuPower.hasBattery ? "battery_horiz_075" : "power"

        SettingValueRow {
            objectName: "batteryLevel"
            visible: CortetsuPower.hasBattery
            title: qsTr("Carga")
            value: qsTr("%1 %").arg(CortetsuPower.percent)
            attention: CortetsuPower.critical
        }

        SettingValueRow {
            objectName: CortetsuPower.hasBattery ? "" : "noBattery"
            title: qsTr("Fuente")
            detail: CortetsuPower.hasBattery ? ""
                : CortetsuPower.laptopBattery ? qsTr("UPower no da una lectura de la batería")
                : qsTr("Este equipo no informa de una batería")
            value: CortetsuPower.onBattery ? qsTr("Batería")
                : CortetsuPower.charging ? qsTr("Corriente, cargando") : qsTr("Corriente")
        }

        SettingValueRow {
            visible: CortetsuPower.hasBattery
            title: CortetsuPower.charging ? qsTr("Carga completa en") : qsTr("Autonomía estimada")
            value: root.context.formatDuration(CortetsuPower.charging ? CortetsuPower.timeToFull : CortetsuPower.timeToEmpty)
        }

        SettingSliderRow {
            objectName: "batteryLowWarning"
            visible: CortetsuPower.hasBattery
            title: qsTr("Avisar con la batería al")
            valueText: CortetsuConfig.batteryLowWarningPercent > 0
                ? qsTr("%1 %").arg(CortetsuConfig.batteryLowWarningPercent) : qsTr("Nunca")
            from: 0
            to: 100
            step: 5
            value: CortetsuConfig.batteryLowWarningPercent
            onMoved: value => {
                CortetsuConfig.batteryLowWarningPercent = Math.round(value / 5) * 5;
                CortetsuConfig.save();
            }
        }
    }

    // The same choice as the Hub popout and Ajustes rápidos, read back from
    // power-profiles-daemon. Limits and automation stay in Hardware.
    SettingsGroup {
        title: qsTr("Perfil de energía")
        icon: "bolt"

        SettingChoiceChips {
            objectName: "powerProfile"
            options: [
                { value: PowerProfile.PowerSaver, label: qsTr("Ahorro"), icon: "energy_savings_leaf", name: "profile-saver" },
                { value: PowerProfile.Balanced, label: qsTr("Equilibrado"), icon: "balance", name: "profile-balanced" }
            ].concat(PowerProfiles.hasPerformanceProfile
                ? [{ value: PowerProfile.Performance, label: qsTr("Rendimiento"), icon: "rocket_launch", name: "profile-performance" }]
                : [])
            current: PowerProfiles.profile
            status: PowerProfiles.degradationReason !== PerformanceDegradationReason.None ? "error" : ""
            statusText: qsTr("Rendimiento limitado: %1").arg(
                PerformanceDegradationReason.toString(PowerProfiles.degradationReason))
            onChosen: value => PowerProfiles.profile = value
        }

        SettingActionRow {
            title: qsTr("Límites y automatización")
            detail: qsTr("Límites de potencia y cambio de perfil automático, en Hardware → Energía")
            actionLabel: qsTr("Abrir Hardware")
            actionIcon: "memory"
            onActivated: root.context.openSurface("hardware")
        }
    }

    SettingsGroup {
        title: qsTr("Reposo")
        icon: "bedtime"
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
            title: qsTr("Bloquear antes de suspender")
            detail: qsTr("Pedir la contraseña al volver de la suspensión")
            checked: CortetsuConfig.idleLockBeforeSleep
            onToggled: value => { CortetsuConfig.idleLockBeforeSleep = value; CortetsuConfig.save(); }
        }
    }

    SettingsGroup {
        title: qsTr("Excepciones al reposo")
        icon: "do_not_disturb_on"
        detail: qsTr("Cuándo no se apaga la pantalla ni se suspende; el bloqueo sigue")
        collapsible: true

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
    }
}
