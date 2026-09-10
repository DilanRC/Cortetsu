pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "../services"
import "."
import "dashboard"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled
                && CortetsuConfig.dashboard.showDashboard
            screen: modelData
            name: "dashboard"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: window.dashboardEnabled && screenState?.dashboard
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None
            mask: window.dashboardEnabled && window.screenState?.dashboard ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Rectangle {
                anchors.fill: parent
                visible: window.dashboardEnabled && (window.screenState?.dashboard ?? false)
                color: Qt.alpha(CortetsuDesign.colorScrim, 0.34)
            }
            Dash {
                anchors.centerIn: parent
                visible: window.dashboardEnabled && (window.screenState?.dashboard ?? false)
                screenState: window.screenState
                facePicker: null
            }
            Shortcut {
                sequence: "Escape"
                enabled: window.dashboardEnabled && (window.screenState?.dashboard ?? false)
                onActivated: window.screenState.dashboard = false
            }
        }
    }
}
