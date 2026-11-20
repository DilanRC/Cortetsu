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
    // Up from a control: back to the dashboard's zones.
    signal leaveRequested()

    // Keyboard: the dashboard's Down enters here; Left and Right move
    // between the visible controls, Up leaves. Tab keeps cycling zones.
    readonly property var controls: [dnd, game, profile, context].filter(item => item.visible)
    function focusFirst(): void {
        if (controls.length > 0)
            controls[0].forceActiveFocus(Qt.TabFocusReason);
    }
    function step(item: Item, delta: int): void {
        const at = controls.indexOf(item);
        const next = controls[Math.max(0, Math.min(controls.length - 1, at + delta))];
        if (next)
            next.forceActiveFocus(Qt.TabFocusReason);
    }

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
        id: dnd
        objectName: "dashDnd"
        Keys.onLeftPressed: root.step(dnd, -1)
        Keys.onRightPressed: root.step(dnd, 1)
        Keys.onUpPressed: root.leaveRequested()
        compact: true
        icon: Notifs.dnd ? "do_not_disturb_on" : "notifications"
        label: qsTr("No molestar")
        active: Notifs.dnd
        tooltipText: Notifs.dnd ? qsTr("Desactivar No molestar") : qsTr("Activar No molestar")
        onClicked: Notifs.toggleDnd()
    }

    CortetsuButton {
        id: game
        objectName: "dashGameMode"
        Keys.onLeftPressed: root.step(game, -1)
        Keys.onRightPressed: root.step(game, 1)
        Keys.onUpPressed: root.leaveRequested()
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
        id: profile
        objectName: "dashPowerProfile"
        Keys.onLeftPressed: root.step(profile, -1)
        Keys.onRightPressed: root.step(profile, 1)
        Keys.onUpPressed: root.leaveRequested()
        compact: true
        icon: root.profileIcons[PowerProfiles.profile] ?? "balance"
        label: root.profileLabels[PowerProfiles.profile] ?? qsTr("Energía")
        tooltipText: qsTr("Cambiar el perfil de energía")
        onClicked: root.nextProfile()
    }

    // As in the control centre: with a context active, its way out; with
    // none, the page where one is chosen.
    CortetsuButton {
        id: context
        objectName: "dashContext"
        Keys.onLeftPressed: root.step(context, -1)
        Keys.onRightPressed: root.step(context, 1)
        Keys.onUpPressed: root.leaveRequested()
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
