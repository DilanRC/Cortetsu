pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Services.UPower
import "../../components"
import "../../services"
import ".."
import "../../theme"
import "../CortetsuOverlayPolicy.js" as OverlayPolicy
import "../settings" as SettingsModule

// Quick controls under the hour. Each button reads and writes the service
// that owns the state (Notifs, GameMode, PowerProfiles, CortetsuContexts);
// `active` follows the confirmed value, so a refused change never shows as
// done. Detail and every other option stay in the control centre and
// Settings.
RowLayout {
    id: root

    // The dashboard's screen, to open Ajustes → Contextos from it.
    property var screenState: null

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

    // As in the control centre: with a context active, its way out; with
    // none, the page where one is chosen.
    CortetsuButton {
        objectName: "dashContext"
        compact: true
        icon: CortetsuContexts.active?.icon ?? "tune"
        label: CortetsuContexts.active ? qsTr("Salir de %1").arg(CortetsuContexts.active.name) : qsTr("Contextos")
        active: CortetsuContexts.active !== null
        tooltipText: CortetsuContexts.active ? qsTr("Desactiva el contexto y restaura los ajustes anteriores")
            : qsTr("Elegir un contexto en Ajustes")
        onClicked: {
            if (CortetsuContexts.active) {
                CortetsuContexts.deactivate();
            } else if (root.screenState) {
                SettingsModule.SettingsController.select("contexts");
                OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, "settings");
            }
        }
    }
}
