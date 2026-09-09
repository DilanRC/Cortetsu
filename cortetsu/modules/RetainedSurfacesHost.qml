pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "."
import "overview" as Overview
import "clipboard" as Clipboard
import "hardware" as Hardware
import "display" as Display
import "wallpaper" as Wallpaper
import "calendar" as Calendar
import "CortetsuDesign.js" as CortetsuDesign

// Retained surfaces have their own overlay window. Keeping them out of the
// shared drawer window gives every full surface a stable layer, focus policy,
// and input mask without competing with BottomHub popouts.
Scope {
    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool surfaceOpen: screenState?.cortetsuState?.retainedOverlayOpen ?? false

            screen: modelData
            name: "retained-surfaces"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: surfaceOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: surfaceOpen ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Rectangle {
                anchors.fill: parent
                visible: window.surfaceOpen
                color: Qt.alpha(CortetsuDesign.colorSumi, 0.78)
                z: -1
            }

            Overview.Wrapper {
                screen: window.modelData
                screenState: window.screenState
                anchors.fill: parent
            }
            Clipboard.Wrapper {
                screen: window.modelData
                screenState: window.screenState
                anchors.fill: parent
            }
            Hardware.Wrapper {
                screen: window.modelData
                screenState: window.screenState
                anchors.fill: parent
            }
            Display.Wrapper {
                screen: window.modelData
                screenState: window.screenState
                anchors.fill: parent
            }
            Wallpaper.Wrapper {
                screen: window.modelData
                screenState: window.screenState
                anchors.fill: parent
            }
            Calendar.Wrapper {
                screenState: window.screenState
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
            }

            Shortcut {
                sequence: "Escape"
                enabled: window.surfaceOpen
                onActivated: window.screenState?.cortetsuState?.closeRetainedOverlays()
            }
        }
    }
}
