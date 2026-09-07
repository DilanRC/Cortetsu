pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import "dashboard"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: ShellState.forActive()
            screen: modelData
            name: "dashboard"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: screenState?.dashboard ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Rectangle {
                anchors.fill: parent
                visible: window.screenState?.dashboard ?? false
                color: Qt.alpha(CortetsuDesign.colorScrim, 0.34)
            }
            Dash {
                anchors.centerIn: parent
                visible: window.screenState?.dashboard ?? false
                screenState: window.screenState
                facePicker: null
            }
            Shortcut { sequence: "Escape"; enabled: window.screenState?.dashboard ?? false; onActivated: window.screenState.dashboard = false }
        }
    }
}
