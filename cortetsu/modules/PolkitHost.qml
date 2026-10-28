pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "../components/containers"
import "../theme"
import "polkit" as Polkit
import "."

// The session's polkit authentication agent. polkit allows one agent per
// session: if another one holds the slot, or registration fails, Cortetsu
// starts polkit-gnome once so privileged actions still get a prompt.
Scope {
    id: root

    readonly property string fallbackAgent: "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1"
    property bool fallbackStarted: false
    // The screen is fixed when a request starts, so moving the pointer or the
    // focus does not carry the dialog across monitors mid-request.
    property var requestScreen: null

    function activeScreen(): var {
        const monitor = CortetsuHypr.focusedMonitor;
        return CortetsuScreens.screens.find(screen => CortetsuHypr.monitorFor(screen) === monitor)
            ?? CortetsuScreens.screens[0] ?? null;
    }

    // Unplugging the request's monitor, or a request that arrived with no
    // screen at all, would leave it with no dialog.
    Connections {
        target: CortetsuScreens
        function onScreensChanged(): void {
            if (agent.isActive && !CortetsuScreens.screens.includes(root.requestScreen))
                root.requestScreen = root.activeScreen();
        }
    }

    PolkitAgent {
        id: agent
        onAuthenticationRequestStarted: root.requestScreen = root.activeScreen()
    }

    // startup inventory: cortetsu:polkit-fallback
    Timer {
        interval: 5000
        running: !agent.isRegistered && !root.fallbackStarted
        onTriggered: {
            root.fallbackStarted = true;
            console.warn("cortetsu-polkit: agent not registered; starting polkit-gnome");
            Quickshell.execDetached([root.fallbackAgent]);
        }
    }

    LazyLoader {
        active: agent.isActive && !!agent.flow && !!root.requestScreen

        StyledWindow {
            id: window
            screen: root.requestScreen
            name: "polkit"
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            // Darker than the session menu: nothing behind an auth prompt should compete with it.
            Rectangle { anchors.fill: parent; color: Qt.alpha(CortetsuDesign.colorScrim, 0.72) }

            Polkit.PolkitDialog {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 48)
                flow: agent.flow
                focus: true
            }
        }
    }
}
