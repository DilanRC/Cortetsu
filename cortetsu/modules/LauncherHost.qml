pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components.containers
import qs.services
import "launcher"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: ShellState.forActive()
            screen: modelData
            name: "launcher"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: screenState?.launcher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Content {
                id: launcher
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Math.max(96, parent.height * 0.12)
                visible: window.screenState?.launcher ?? false
                screenState: window.screenState
                panels: null
                maxHeight: parent.height * 0.72
            }
            Connections {
                target: window.screenState
                function onLauncherChanged(): void {
                    if (window.screenState.launcher)
                        Qt.callLater(() => launcher.focusSearch());
                }
            }
            Shortcut { sequence: "Escape"; enabled: window.screenState?.launcher ?? false; onActivated: window.screenState.launcher = false }
        }
    }
}
