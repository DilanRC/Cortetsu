pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography

// The machine's own actions from the lock: power off, restart, and the
// display manager's greeter to sign in as someone else or into another
// session (Hyprland, Sway…), with this session kept as it is. Powering off
// or restarting asks for a second press; none of them unlocks anything.
// A button hands the keyboard back to the password.
RowLayout {
    id: root

    signal handBackFocus()

    // The one armed action, "" when none; a second press within 4 s runs it.
    property string armed: ""
    // Desktop sessions installed (their Name=), shown with the switch.
    property var sessions: []
    property bool canSwitch: false

    spacing: 10

    Timer {
        id: disarm
        interval: 4000
        onTriggered: root.armed = ""
    }

    function press(id: string, command: var): void {
        if (root.armed !== id) {
            root.armed = id;
            disarm.restart();
        } else {
            root.armed = "";
            Quickshell.execDetached(command);
        }
        root.handBackFocus();
    }

    // Installed sessions, read once from their desktop files.
    Process {
        running: true
        command: ["sh", "-c", "grep -h -m1 '^Name=' /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop 2>/dev/null | cut -d= -f2- | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: root.sessions = text.split("\n").map(s => s.trim()).filter(s => s.length > 0)
        }
    }
    // The display manager can show its greeter while this session stays.
    Process {
        running: true
        command: ["busctl", "--system", "get-property", "org.freedesktop.DisplayManager",
            "/org/freedesktop/DisplayManager/Seat0", "org.freedesktop.DisplayManager.Seat", "CanSwitch"]
        stdout: StdioCollector { onStreamFinished: root.canSwitch = text.trim() === "b true" }
    }

    Repeater {
        model: [
            { id: "poweroff", icon: "power_settings_new", tip: qsTr("Apagar"), danger: true, command: ["systemctl", "poweroff"] },
            { id: "reboot", icon: "restart_alt", tip: qsTr("Reiniciar"), danger: true, command: ["systemctl", "reboot"] }
        ]
        delegate: CortetsuButton {
            required property var modelData
            objectName: `lockPower-${modelData.id}`
            pill: true
            activeFocusOnTab: false
            danger: root.armed === modelData.id
            icon: modelData.icon
            label: root.armed === modelData.id ? qsTr("¿%1? Pulsa otra vez").arg(modelData.tip) : ""
            tooltipText: qsTr("%1 (pide confirmación)").arg(modelData.tip)
            onClicked: root.press(modelData.id, modelData.command)
        }
    }

    CortetsuButton {
        objectName: "lockSwitchSession"
        visible: root.canSwitch
        pill: true
        activeFocusOnTab: false
        icon: "switch_account"
        label: qsTr("Cambiar usuario o sesión")
        tooltipText: root.sessions.length > 0
            ? qsTr("Abre el inicio de sesión sin cerrar esta. Sesiones instaladas: %1").arg(root.sessions.join(", "))
            : qsTr("Abre el inicio de sesión sin cerrar esta")
        onClicked: {
            Quickshell.execDetached(["busctl", "--system", "call", "org.freedesktop.DisplayManager",
                "/org/freedesktop/DisplayManager/Seat0", "org.freedesktop.DisplayManager.Seat", "SwitchToGreeter"]);
            root.handBackFocus();
        }
    }
}
