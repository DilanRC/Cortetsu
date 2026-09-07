import QtQuick
import QtQuick.Layouts
import Quickshell
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Column {
    id: root
    required property var screenState
    property var pendingAction: null
    padding: CortetsuDesign.spacingStandard
    spacing: CortetsuDesign.spacingCompact

    function run(action): void {
        if (!action)
            return;
        if (pendingAction !== action) {
            pendingAction = action;
            confirmTimer.restart();
            return;
        }
        pendingAction = null;
        confirmTimer.stop();
        Quickshell.execDetached(action.command);
        root.screenState.session = false;
    }

    Timer {
        id: confirmTimer
        interval: 4000
        onTriggered: root.pendingAction = null
    }

    Repeater {
        model: [
            { label: qsTr("Log out"), icon: "logout", command: ["hyprctl", "dispatch", "exit"] },
            { label: qsTr("Shutdown"), icon: "power_settings_new", command: ["systemctl", "poweroff"] },
            { label: qsTr("Hibernate"), icon: "bedtime", command: ["systemctl", "hibernate"] },
            { label: qsTr("Reboot"), icon: "restart_alt", command: ["systemctl", "reboot"] }
        ]
        delegate: Rectangle {
            required property var modelData
            implicitWidth: 220
            implicitHeight: 52
            radius: CortetsuDesign.radiusMedium
            color: hovered ? CortetsuDesign.colorSurfaceHigh : CortetsuDesign.colorSurface
            property bool hovered: false

            Row {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard
                Text {
                    text: modelData.icon
                    color: CortetsuDesign.colorPrimary
                    font.family: CortetsuTypography.iconFamily
                    font.pixelSize: CortetsuTypography.iconMediumPx
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pendingAction === modelData
                        ? qsTr("Confirm %1").arg(modelData.label)
                        : modelData.label
                    color: CortetsuDesign.colorWashi
                    font.family: CortetsuTypography.uiFamily
                    font.pixelSize: CortetsuTypography.bodyPx
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.hovered = true
                onExited: parent.hovered = false
                onClicked: root.run(modelData.command)
            }
        }
    }
}
