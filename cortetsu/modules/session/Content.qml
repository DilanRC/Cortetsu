import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Column {
    id: root

    required property var screenState
    property string pendingAction: ""
    property var deferredCommand: null

    padding: CortetsuDesign.spacingStandard
    spacing: CortetsuDesign.spacingCompact

    readonly property var actions: [
        {
            id: "lock",
            label: qsTr("Lock"),
            detail: qsTr("Secure this session"),
            icon: "lock",
            command: ["hyprctl", "dispatch", "global", "cortetsu:lock"],
            confirm: false,
            danger: false,
            lockBefore: false
        },
        {
            id: "suspend",
            label: qsTr("Suspend"),
            detail: qsTr("Lock, then sleep"),
            icon: "mode_standby",
            command: ["systemctl", "suspend"],
            confirm: false,
            danger: false,
            lockBefore: true
        },
        {
            id: "logout",
            label: qsTr("Log out"),
            detail: qsTr("End the Hyprland session"),
            icon: "logout",
            command: ["hyprctl", "dispatch", "exit"],
            confirm: true,
            danger: true,
            lockBefore: false
        },
        {
            id: "hibernate",
            label: qsTr("Hibernate"),
            detail: qsTr("Save memory to disk"),
            icon: "bedtime",
            command: ["systemctl", "hibernate"],
            confirm: true,
            danger: false,
            lockBefore: false
        },
        {
            id: "reboot",
            label: qsTr("Reboot"),
            detail: qsTr("Restart the computer"),
            icon: "restart_alt",
            command: ["systemctl", "reboot"],
            confirm: true,
            danger: true,
            lockBefore: false
        },
        {
            id: "shutdown",
            label: qsTr("Shutdown"),
            detail: qsTr("Power off the computer"),
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
        if (!action || !action.command)
            return;

        pendingAction = "";
        confirmTimer.stop();

        if (action.lockBefore) {
            Quickshell.execDetached(["hyprctl", "dispatch", "global", "cortetsu:lock"]);
            deferredCommand = action.command;
            deferredTimer.restart();
        } else {
            Quickshell.execDetached(action.command);
        }

        root.screenState.session = false;
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
        interval: 220
        onTriggered: {
            if (root.deferredCommand)
                Quickshell.execDetached(root.deferredCommand);
            root.deferredCommand = null;
        }
    }

    Repeater {
        model: root.actions

        delegate: CortetsuActionRow {
            id: actionRow
            required property var modelData

            width: 328
            icon: actionRow.modelData.icon
            title: root.pendingAction === actionRow.modelData.id
                ? qsTr("Confirm %1").arg(actionRow.modelData.label)
                : actionRow.modelData.label
            subtitle: root.pendingAction === actionRow.modelData.id
                ? qsTr("Press again within 4 seconds")
                : actionRow.modelData.detail
            danger: actionRow.modelData.danger
            selected: root.pendingAction === actionRow.modelData.id
            trailingIcon: actionRow.selected ? "warning" : "chevron_right"
            onClicked: root.run(actionRow.modelData)
        }
    }
}
