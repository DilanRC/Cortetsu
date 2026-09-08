pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.modules
import qs.modules.overview as Overview
import qs.modules.clipboard as Clipboard
import qs.modules.hardware as Hardware
import qs.modules.display as Display
import qs.modules.wallpaper as Wallpaper
import qs.modules.calendar as Calendar

// Retained surfaces have their own overlay window. Keeping them out of the
// shared drawer window gives every full surface a stable layer, focus policy,
// and input mask without competing with BottomHub popouts.
Scope {
    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forActive()
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
                color: Qt.alpha("#0d1017", 0.78)
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
