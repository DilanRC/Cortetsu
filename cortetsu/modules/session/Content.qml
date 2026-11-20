import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../../services"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Column {
    id: root

    required property var screenState
    property var lockController: null
    property string pendingAction: ""
    property string failedAction: ""
    // The action waiting for the lock before it runs.
    property var deferredCommand: null
    property string deferredState: "idle"
    // Seconds left on an armed confirmation, shown on the row.
    property int confirmRemaining: 0
    readonly property int confirmSeconds: 4

    padding: CortetsuDesign.spacingStandard
    spacing: CortetsuDesign.spacingCompact

    readonly property var actions: [
        {
            id: "lock",
            seal: "錠",
            label: qsTr("Bloquear"),
            detail: qsTr("Proteger esta sesión"),
            icon: "lock",
            lockOnly: true,
            confirm: false,
            danger: false,
            lockBefore: false
        },
        {
            id: "suspend",
            seal: "眠",
            label: qsTr("Suspender"),
            detail: qsTr("Bloquear y suspender"),
            icon: "mode_standby",
            sleepMode: "suspend",
            confirm: false,
            danger: false,
            lockBefore: true
        },
        {
            id: "logout",
            seal: "出",
            label: qsTr("Cerrar sesión"),
            detail: qsTr("Finalizar la sesión de Hyprland"),
            icon: "logout",
            hyprAction: "exit",
            confirm: true,
            danger: true,
            lockBefore: false
        },
        {
            id: "hibernate",
            seal: "冬",
            label: qsTr("Hibernar"),
            detail: qsTr("Guardar la memoria en el disco"),
            icon: "bedtime",
            sleepMode: "hibernate",
            confirm: true,
            danger: false,
            lockBefore: false
        },
        {
            id: "reboot",
            seal: "再",
            label: qsTr("Reiniciar"),
            detail: qsTr("Reiniciar el equipo"),
            icon: "restart_alt",
            command: ["systemctl", "reboot"],
            confirm: true,
            danger: true,
            lockBefore: false
        },
        {
            id: "shutdown",
            seal: "止",
            label: qsTr("Apagar"),
            detail: qsTr("Apagar el equipo"),
            icon: "power_settings_new",
            command: ["systemctl", "poweroff"],
            confirm: true,
            danger: true,
            lockBefore: false
        }
    ]

    function close(): void {
        pendingAction = "";
        confirmTimer.stop();
        countdown.stop();
        root.screenState.session = false;
    }

    // Sleep modes follow what logind reports now; a mode it would refuse is
    // shown as unavailable instead of failing silently after the lock.
    function available(action): bool {
        return !action.sleepMode || CortetsuSession.available(action.sleepMode);
    }

    Component.onCompleted: CortetsuSession.refreshCapabilities()
    onVisibleChanged: if (visible) CortetsuSession.refreshCapabilities()

    function execute(action): void {
        if (!action || !(action.sleepMode || action.command || action.dispatch || action.hyprAction || action.lockOnly) || !available(action))
            return;

        pendingAction = "";
        failedAction = "";
        confirmTimer.stop();
        countdown.stop();

        if (action.lockOnly) {
            // The lock is owned by this shell; a compositor round trip can
            // only fail (and did, silently, with the Lua dispatcher syntax).
            if (!lockController) {
                failedAction = action.id;
                return;
            }
            lockController.requestLock();
            root.screenState.session = false;
            return;
        }

        if (action.hyprAction === "exit") {
            CortetsuHypr.exitHyprland();
            root.screenState.session = false;
            return;
        }

        if (action.lockBefore) {
            if (!lockController)
                return;

            deferredCommand = action;
            deferredState = "requestingLock";
            deferredTimer.restart();
            lockController.requestLock();
            if (lockController.lockReady)
                Qt.callLater(root.dispatchDeferred);
        } else {
            launch(action);
        }

        root.screenState.session = false;
    }

    function launch(action): void {
        if (action.sleepMode)
            CortetsuSession.request(action.sleepMode);
        else
            Quickshell.execDetached(action.command);
    }

    function dispatchDeferred(): void {
        if (deferredState !== "requestingLock" || !deferredCommand || !lockController.lockReady)
            return;

        const action = deferredCommand;
        deferredCommand = null;
        deferredState = "dispatched";
        deferredTimer.stop();
        launch(action);
        Qt.callLater(() => deferredState = "idle");
    }

    function run(action): void {
        if (!action || !available(action))
            return;

        if (action.confirm && pendingAction !== action.id) {
            pendingAction = action.id;
            confirmRemaining = confirmSeconds;
            confirmTimer.restart();
            countdown.restart();
            return;
        }

        execute(action);
    }

    // Escape disarms a confirmation before it closes the menu.
    function cancelPending(): bool {
        if (pendingAction.length === 0)
            return false;
        pendingAction = "";
        confirmTimer.stop();
        countdown.stop();
        return true;
    }

    Timer {
        id: confirmTimer
        interval: root.confirmSeconds * 1000
        onTriggered: {
            root.pendingAction = "";
            countdown.stop();
        }
    }

    // Runs only while a confirmation is armed.
    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: root.confirmRemaining = Math.max(0, root.confirmRemaining - 1)
    }

    Timer {
        id: deferredTimer
        interval: 1000
        onTriggered: {
            if (root.deferredState === "requestingLock") {
                root.deferredCommand = null;
                root.deferredState = "idle";
            }
        }
    }

    Connections {
        target: root.lockController ? root.lockController.lock : null

        function onLockedChanged(): void {
            if (root.lockController.lockReady)
                root.dispatchDeferred();
        }
    }

    // Two groups: what keeps this session (lock, sleep) and what ends it
    // (log out, restart, power off). The second asks twice, with the time
    // left to confirm on the row itself.
    Repeater {
        model: root.actions

        delegate: Column {
            id: entry
            required property var modelData
            required property int index
            readonly property bool startsEndGroup: entry.modelData.id === "logout"
            width: root.width - root.leftPadding - root.rightPadding
            spacing: CortetsuDesign.spacingCompact

            CortetsuDivider {
                visible: entry.startsEndGroup
                width: parent.width
            }

            CortetsuActionRow {
                id: actionRow
                // Not the delegate itself (the Column is), so the index the
                // row needs for its first-row focus is passed on by hand.
                index: entry.index
                width: parent.width
                icon: entry.modelData.icon
                seal: entry.modelData.seal
                title: root.pendingAction === entry.modelData.id
                    ? qsTr("Confirmar: %1").arg(entry.modelData.label)
                    : entry.modelData.label
                disabled: !root.available(entry.modelData)
                subtitle: actionRow.disabled
                    ? CortetsuSession.reason(entry.modelData.sleepMode)
                    : root.failedAction === entry.modelData.id
                    ? qsTr("No disponible: el bloqueo de sesión no está listo")
                    : root.pendingAction === entry.modelData.id
                        ? (root.confirmRemaining === 1
                            ? qsTr("Pulsa otra vez para confirmar · 1 segundo")
                            : qsTr("Pulsa otra vez para confirmar · %1 segundos").arg(root.confirmRemaining))
                        : entry.modelData.detail
                danger: entry.modelData.danger
                selected: root.pendingAction === entry.modelData.id
                trailingIcon: actionRow.selected ? "warning" : "chevron_right"
                onClicked: root.run(entry.modelData)
            }
        }
    }
}
