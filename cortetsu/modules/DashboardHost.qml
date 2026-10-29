pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "../services"
import "."
import "dashboard"
import "../theme"
import "CortetsuOverlayPolicy.js" as SurfacePolicy
import "drawers"

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled
                && CortetsuConfig.dashboard.showDashboard
            readonly property bool open: window.dashboardEnabled && (screenState?.dashboard ?? false)
            readonly property string keyboardFocusPolicyName: open ? "exclusive" : "none"
            screen: modelData
            name: "dashboard"
            // Mapped only while open: an idle full-screen Overlay layer keeps a
            // fullscreen game from being the monitor's solitary client.
            visible: window.open
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // Exclusive like the launcher: the layer covers the screen, so
            // Escape must reach it however it was opened.
            WlrLayershell.keyboardFocus: window.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: window.open ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            DashboardLayer {
                id: layer
                anchors.fill: parent
                open: window.open
                screenState: window.screenState
            }
            // Window-wide, so Escape closes it wherever focus sits inside.
            Shortcut {
                sequence: "Escape"
                enabled: window.open
                onActivated: layer.close()
            }
            Binding {
                target: window.screenState?.cortetsuState ?? null
                property: "dashboardWindow"
                value: window
                when: !!window.screenState?.cortetsuState
            }
        }
    }
}
