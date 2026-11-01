pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "."
import "session" as Session
import "../theme"
import "CortetsuTypography.js" as CortetsuTypography
import "CortetsuOverlayPolicy.js" as SurfacePolicy
import "drawers"

Scope {
    id: root
    required property var lockController

    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool open: screenState?.session ?? false
            readonly property bool preview: SurfacePolicy.isPreview(screenState, "session")
            readonly property string keyboardFocusPolicyName: open
                ? (preview ? "none" : "exclusive") : "none"
            screen: modelData
            name: "session"
            // Mapped only while open: an idle full-screen Overlay layer keeps a
            // fullscreen game from being the monitor's solitary client.
            visible: open
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: open && !preview
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: open ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Rectangle { anchors.fill: parent; visible: window.open; color: Qt.alpha(CortetsuDesign.colorScrim, 0.54) }

            Item {
                id: panel
                anchors.centerIn: parent
                visible: window.open
                width: Math.min(440, parent.width - 48)
                implicitHeight: contentColumn.implicitHeight + CortetsuDesign.spacingComfortable * 2
                height: implicitHeight

                // The session speaks the dashboard's ink: sumi, wash, grain.
                CortetsuInkPanel {
                    anchors.fill: parent
                    radius: CortetsuDesign.radiusSurface
                    groundAlpha: 0.98
                }

                    Column {
                        id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: CortetsuDesign.spacingComfortable
                    spacing: CortetsuDesign.spacingStandard

                    Row {
                        width: parent.width
                        spacing: CortetsuDesign.spacingStandard
                        anchors.horizontalCenter: parent.horizontalCenter
                        CortetsuEvolvingMark {
                            width: 50; height: 50
                            phase: window.open ? "Awakening" : "Human"
                            monochrome: true
                            monochromeColor: CortetsuDesign.colorPrimary
                            animated: true
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            CortetsuText { text: qsTr("Sesión"); font.family: CortetsuDesign.fontInk; font.weight: Font.Light; textSize: CortetsuTypography.inkTitlePx; color: CortetsuDesign.colorWashi }
                            CortetsuText { text: qsTr("Acciones de energía y sesión"); textSize: CortetsuTypography.bodySmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                        }
                    }

                    CortetsuBrushStroke { width: parent.width; height: 3; ink: CortetsuDesign.colorWashi; inkAlpha: 0.1 }

                    Session.Content {
                        width: parent.width
                        anchors.horizontalCenter: parent.horizontalCenter
                        screenState: window.screenState
                        lockController: root.lockController
                    }
                }
            }

            HoverPreviewTracker {
                hostWindow: window
                screen: window.modelData
                screenState: window.screenState
                surface: "session"
                panel: panel
                previewTriggerContains: (x, y) => CortetsuShellState.componentsFor(window.modelData)
                    ?.interactionWrapper?.previewTriggerContains("session", x, y) ?? false
            }
            Binding {
                target: window.screenState?.cortetsuState ?? null
                property: "sessionWindow"
                value: window
                when: !!window.screenState?.cortetsuState
            }
            Shortcut {
                sequence: "Escape"
                enabled: window.open
                onActivated: SurfacePolicy.closeOn(window.screenState, "session")
            }
        }
    }
}
