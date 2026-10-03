pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../.."
import "../../../services"
import "../../../utils"
import ".."
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Energía")
        detail: qsTr("Lectura de batería y política de reposo")
    }

    DomainHero {
        icon: CortetsuPower.hasBattery
            ? Icons.getBatteryIcon(CortetsuPower.value, root.page.batteryCharging)
            : "power"
        title: CortetsuPower.hasBattery
            ? (root.page.batteryCharging ? qsTr("Batería cargando") : qsTr("Batería en uso"))
            : qsTr("Alimentación externa")
        detail: CortetsuPower.onBattery
            ? qsTr("Funcionando sin alimentación externa")
            : qsTr("Conectado a la alimentación externa")
        value: root.page.batteryStatus
        meta: CortetsuPower.charging
            ? qsTr("Carga completa en %1").arg(root.page.formatDuration(CortetsuPower.timeToFull * 1000))
            : qsTr("Autonomía estimada: %1").arg(root.page.formatDuration(CortetsuPower.timeToEmpty * 1000))
        progress: CortetsuPower.hasBattery ? CortetsuPower.value : -1
        warningState: CortetsuPower.critical
    }

    StatusCard {
        title: CortetsuPower.laptopBattery ? qsTr("Batería") : qsTr("Fuente de energía")
        value: CortetsuPower.hasBattery ? qsTr("%1%").arg(root.page.batteryPercent) : qsTr("Alimentación externa")
        detail: CortetsuPower.onBattery ? qsTr("Funcionando con batería") : qsTr("Conectado a alimentación externa")
        icon: CortetsuPower.hasBattery
            ? Icons.getBatteryIcon(CortetsuPower.value, root.page.batteryCharging)
            : "power"
        activeState: !CortetsuPower.onBattery
        warningState: CortetsuPower.critical
    }

    PreferenceToggle {
        title: qsTr("Evitar reposo durante el audio")
        detail: qsTr("Mantener activa la sesión durante la reproducción")
        icon: "music_note"
        checked: CortetsuConfig.idleInhibitWhenAudio
        onChanged: checked => {
            CortetsuConfig.idleInhibitWhenAudio = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Evitar reposo mientras carga")
        detail: qsTr("Mantener activa la sesión con alimentación externa")
        icon: "power"
        checked: CortetsuConfig.idleInhibitWhenCharging
        onChanged: checked => {
            CortetsuConfig.idleInhibitWhenCharging = checked;
            root.page.savePreference();
        }
    }

    PreferenceToggle {
        title: qsTr("Bloquear antes de suspender")
        detail: qsTr("Bloquear la sesión antes de que el equipo entre en suspensión")
        icon: "lock"
        checked: CortetsuConfig.idleLockBeforeSleep
        onChanged: checked => {
            CortetsuConfig.idleLockBeforeSleep = checked;
            root.page.savePreference();
        }
    }
}
