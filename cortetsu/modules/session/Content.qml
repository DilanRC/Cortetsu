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

        delegate: CortetsuSurface {
            id: actionRow
            required property var modelData

            width: 328
            implicitHeight: 58
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: hovered
                ? Qt.alpha(modelData.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorSurfaceHigh, modelData.danger ? 0.14 : 1.0)
                : CortetsuDesign.colorSurface
            outlined: root.pendingAction === modelData.id
            outlineColor: modelData.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
            property bool hovered: false

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuIcon {
                    text: modelData.icon
                    iconSize: CortetsuTypography.iconMediumPx
                    color: modelData.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorPrimary
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.pendingAction === modelData.id
                            ? qsTr("Confirm %1").arg(modelData.label)
                            : modelData.label
                        textSize: CortetsuTypography.bodyPx
                        font.weight: Font.DemiBold
                        color: root.pendingAction === modelData.id && modelData.danger
                            ? CortetsuDesign.colorVermillion
                            : CortetsuDesign.colorOnSurface
                        elide: Text.ElideRight
                    }

                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.pendingAction === modelData.id
                            ? qsTr("Press again within 4 seconds")
                            : modelData.detail
                        textSize: CortetsuTypography.labelSmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                        elide: Text.ElideRight
                    }
                }

                CortetsuIcon {
                    text: root.pendingAction === modelData.id ? "warning" : "chevron_right"
                    iconSize: CortetsuTypography.iconSmallPx
                    color: root.pendingAction === modelData.id
                        ? (modelData.danger ? CortetsuDesign.colorVermillion : CortetsuDesign.colorWarning)
                        : CortetsuDesign.colorOnSurfaceVariant
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: actionRow.hovered = true
                onExited: actionRow.hovered = false
                onClicked: root.run(actionRow.modelData)
            }
        }
    }
}
