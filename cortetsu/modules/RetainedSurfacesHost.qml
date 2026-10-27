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
import "keyboards" as Keyboards
import "../theme"
import "ScrimHit.js" as ScrimHit

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
            // Mapped only while a surface is open or still animating out: an
            // idle full-screen Overlay layer keeps a fullscreen game from being
            // the monitor's solitary client.
            visible: surfaceOpen || surfaces.children.some(child => child.visible)
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: surfaceOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: surfaceOpen ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            // A press on the bell where no panel covers it. A Keyboards
            // capture or write blocks pointer dismissal; it blocks this too.
            // A fullscreen window blocks opening the sidebar, as for SUPER+N.
            function reachesBell(x: real, y: real): bool {
                return !keyboards.dismissBlocked && !CortetsuHypr.focusedFullscreen
                    && (screenState?.cortetsuState?.bottomHub?.notificationsButtonContains(x, y) ?? false)
                    && ScrimHit.backdropOnly(surfaces, x, y);
            }

            Rectangle {
                anchors.fill: parent
                visible: window.surfaceOpen && !window.screenState?.cortetsuState?.overview
                color: Qt.alpha(CortetsuDesign.colorSumi, 0.34)
                z: -1
            }

            Item {
                id: surfaces
                anchors.fill: parent

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
                Keyboards.Wrapper {
                    id: keyboards
                    screen: window.modelData
                    screenState: window.screenState
                    anchors.fill: parent
                }
                Calendar.Wrapper {
                    screenState: window.screenState
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                }
            }

            // The scrim is modal and covers Bottom Hub (Top layer), so a click
            // on the bell would only dismiss the surface. The bell action
            // closes every retained surface anyway (as SUPER+N does), so a
            // click on it runs that action in one step. Every other press, and
            // any press on a panel, goes on to the surface underneath.
            MouseArea {
                anchors.fill: parent
                enabled: window.surfaceOpen && !(window.screenState?.cortetsuState?.overview ?? false)
                onPressed: mouse => mouse.accepted = window.reachesBell(mouse.x, mouse.y)
                onClicked: window.screenState?.cortetsuState?.bottomHub?.activateNotifications()
            }

            Shortcut {
                sequence: "Escape"
                enabled: window.surfaceOpen
                onActivated: window.screenState?.cortetsuState?.closeRetainedOverlays()
            }
        }
    }
}
