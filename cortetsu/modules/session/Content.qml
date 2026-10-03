import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import ".."
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

Column {
    id: root

    required property var screenState
    property var lockController: null
    property string pendingAction: ""
    property string failedAction: ""
    property var deferredCommand: null
    property string deferredState: "idle"

    padding: CortetsuDesign.spacingStandard
    spacing: CortetsuDesign.spacingCompact

    readonly property var actions: [
        {
            id: "lock",
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
            label: qsTr("Suspender"),
            detail: qsTr("Bloquear y suspender"),
            icon: "mode_standby",
            command: ["systemctl", "suspend"],
            confirm: false,
            danger: false,
            lockBefore: true
        },
        {
            id: "logout",
            label: qsTr("Cerrar sesión"),
            detail: qsTr("Finalizar la sesión de Hyprland"),
            icon: "logout",
            dispatch: CortetsuHypr.usingLua ? "hl.dsp.exit()" : "exit",
            confirm: true,
            danger: true,
            lockBefore: false
        },
        {
            id: "hibernate",
            label: qsTr("Hibernar"),
            detail: qsTr("Guardar la memoria en el disco"),
            icon: "bedtime",
            command: ["systemctl", "hibernate"],
            confirm: true,
            danger: false,
            lockBefore: false
        },
        {
            id: "reboot",
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
        root.screenState.session = false;
    }

    function execute(action): void {
        if (!action || !(action.command || action.dispatch || action.lockOnly))
            return;

        pendingAction = "";
        confirmTimer.stop();

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

        if (action.dispatch) {
            CortetsuHypr.dispatch(action.dispatch);
            root.screenState.session = false;
            return;
        }

        if (action.lockBefore) {
            if (!lockController)
                return;

            deferredCommand = action.command;
            deferredState = "requestingLock";
            deferredTimer.restart();
            lockController.requestLock();
            if (lockController.lockReady)
                Qt.callLater(root.dispatchDeferred);
        } else {
            Quickshell.execDetached(action.command);
        }

        root.screenState.session = false;
    }

    function dispatchDeferred(): void {
        if (deferredState !== "requestingLock" || !deferredCommand || !lockController.lockReady)
            return;

        const command = deferredCommand;
        deferredCommand = null;
        deferredState = "dispatched";
        deferredTimer.stop();
        Quickshell.execDetached(command);
        Qt.callLater(() => deferredState = "idle");
    }

    function run(action): void {
        if (!action)
            return;

        if (action.confirm && pendingAction !== action.id) {
            pendingAction = action.id;
            confirmTimer.restart();
            return;
        }

        execute(action);
    }

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: root.pendingAction = ""
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

    Repeater {
        model: root.actions

        delegate: CortetsuActionRow {
            id: actionRow
            required property var modelData

            width: root.width
            icon: actionRow.modelData.icon
            title: root.pendingAction === actionRow.modelData.id
                ? qsTr("Confirmar %1").arg(actionRow.modelData.label)
                : actionRow.modelData.label
            subtitle: root.failedAction === actionRow.modelData.id
                ? qsTr("No disponible: el bloqueo de sesión no está listo")
                : root.pendingAction === actionRow.modelData.id
                    ? qsTr("Pulsa otra vez en 4 segundos")
                    : actionRow.modelData.detail
            danger: actionRow.modelData.danger
            selected: root.pendingAction === actionRow.modelData.id
            trailingIcon: actionRow.selected ? "warning" : "chevron_right"
            onClicked: root.run(actionRow.modelData)
        }
    }
}
