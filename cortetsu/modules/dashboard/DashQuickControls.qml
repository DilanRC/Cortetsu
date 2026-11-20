pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../components"
import "../../services"
import ".."
import "../../theme"

// Quick controls under the hour. Each button reads and writes the service
// that owns the state (Notifs, GameMode, PowerProfiles, CortetsuContexts);
// `active` follows the confirmed value, so a refused change never shows as
// done. Detail and every other option stay in the control centre and
// Settings.
RowLayout {
    id: root

    readonly property var profiles: [PowerProfile.PowerSaver, PowerProfile.Balanced]
        .concat(PowerProfiles.hasPerformanceProfile ? [PowerProfile.Performance] : [])
    readonly property var profileLabels: ({
        [PowerProfile.PowerSaver]: qsTr("Ahorro"),
        [PowerProfile.Balanced]: qsTr("Equilibrado"),
        [PowerProfile.Performance]: qsTr("Rendimiento")
    })
    readonly property var profileIcons: ({
        [PowerProfile.PowerSaver]: "energy_savings_leaf",
        [PowerProfile.Balanced]: "balance",
        [PowerProfile.Performance]: "bolt"
    })

    function nextProfile(): void {
        const at = profiles.indexOf(PowerProfiles.profile);
        PowerProfiles.profile = profiles[(at + 1) % profiles.length];
    }

    spacing: CortetsuDesign.spacingCompact

    CortetsuButton {
        objectName: "dashDnd"
        compact: true
        icon: Notifs.dnd ? "do_not_disturb_on" : "notifications"
        label: qsTr("No molestar")
        active: Notifs.dnd
        tooltipText: Notifs.dnd ? qsTr("Desactivar No molestar") : qsTr("Activar No molestar")
        onClicked: Notifs.toggleDnd()
    }

    CortetsuButton {
        objectName: "dashGameMode"
        compact: true
        icon: "sports_esports"
        label: GameMode.busy ? qsTr("Aplicando…") : qsTr("Modo juego")
        active: GameMode.enabled
        disabled: GameMode.busy
        tooltipText: GameMode.needsRecovery ? qsTr("Recuperar la configuración de Hyprland")
            : GameMode.enabled ? qsTr("Desactivar el modo juego") : qsTr("Activar el modo juego")
        onClicked: GameMode.toggle()
    }

    CortetsuButton {
        objectName: "dashPowerProfile"
        compact: true
        icon: root.profileIcons[PowerProfiles.profile] ?? "balance"
        label: root.profileLabels[PowerProfiles.profile] ?? qsTr("Energía")
        tooltipText: qsTr("Cambiar el perfil de energía")
        onClicked: root.nextProfile()
    }

    CortetsuButton {
        objectName: "dashContext"
        visible: CortetsuContexts.active !== null
        compact: true
        icon: CortetsuContexts.active?.icon ?? "tune"
        label: qsTr("Salir de %1").arg(CortetsuContexts.active?.name ?? "")
        active: true
        tooltipText: qsTr("Desactiva el contexto y restaura los ajustes anteriores")
        onClicked: CortetsuContexts.deactivate()
    }
}
