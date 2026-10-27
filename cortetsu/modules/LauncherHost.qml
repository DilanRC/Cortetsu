pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/containers"
import "../services"
import "."
import "launcher"
import "../theme"

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            screen: modelData
            name: "launcher"
            // Mapped only while open: an idle full-screen Overlay layer keeps a
            // fullscreen game from being the monitor's solitary client.
            visible: screenState?.launcher ?? false
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: screenState?.launcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: window.screenState?.launcher ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            // Same policy as the retained surfaces: a click inside this
            // window but outside the panel dismisses it.
            MouseArea {
                anchors.fill: parent
                enabled: window.screenState?.launcher ?? false
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const inside = mouse.x >= launcher.x && mouse.x < launcher.x + launcher.width
                        && mouse.y >= launcher.y && mouse.y < launcher.y + launcher.height;
                    if (!inside)
                        window.screenState.launcher = false;
                }
            }

            Content {
                id: launcher
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: window.screenState?.launcher ?? false
                screenState: window.screenState
                panels: null
                maxHeight: parent.height * 0.72
            }
            Connections {
                target: window.screenState
                function onLauncherChanged(): void {
                    if (!window.screenState.launcher)
                        return;
                    // Whatever path opened it (shortcut, IPC, hover, showall),
                    // no other screen keeps a launcher holding the keyboard.
                    CortetsuShellState.closeLaunchers(window.screenState);
                    Qt.callLater(() => launcher.focusSearch());
                }
            }
            Shortcut { sequence: "Escape"; enabled: window.screenState?.launcher ?? false; onActivated: window.screenState.launcher = false }
        }
    }
}
