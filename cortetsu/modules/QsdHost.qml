pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "../services"
import "."
import "qsd"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)

            screen: modelData
            name: "qsd"
            // Keep the layer surface alive; the drawer itself owns transient
            // visibility so the first open does not race layer allocation.
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            mask: window.screenState?.qsd ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Item {
                id: drawer
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 400
                visible: window.screenState?.qsd ?? false

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorSumi, 0.985)
                    radiusValue: CortetsuDesign.radiusSurface
                    outlined: true
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.72)
                }

                Content {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSection
                    screenState: window.screenState
                    screen: window.modelData
                }

                MouseArea {
                    id: drawerMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                    onEntered: window.screenState.qsdDrawerHovered = true
                    onExited: window.screenState.qsdDrawerHovered = false
                }
            }

            Timer {
                id: closeGrace
                interval: 260
                repeat: false
                onTriggered: {
                    const state = window.screenState;
                    if (state?.qsd && !state.qsdOpenedByShortcut
                        && !state.qsdEdgeHovered && !state.qsdDrawerHovered
                        && !window.activeFocus)
                        state.qsd = false;
                }
            }

            Connections {
                target: window.screenState
                function onQsdChanged(): void {
                    if (window.screenState.qsd && !window.screenState.qsdOpenedByShortcut)
                        closeGrace.restart();
                    else
                        closeGrace.stop();
                }
                function onQsdEdgeHoveredChanged(): void {
                    if (!window.screenState.qsdEdgeHovered && window.screenState.qsd
                        && !window.screenState.qsdOpenedByShortcut)
                        closeGrace.restart();
                    else if (window.screenState.qsdEdgeHovered)
                        closeGrace.stop();
                }
                function onQsdDrawerHoveredChanged(): void {
                    if (window.screenState.qsdDrawerHovered)
                        closeGrace.stop();
                    else if (window.screenState.qsd && !window.screenState.qsdOpenedByShortcut)
                        closeGrace.restart();
                }
            }

            Shortcut {
                sequence: "Escape"
                enabled: window.screenState?.qsd ?? false
                onActivated: {
                    window.screenState.qsdOpenedByShortcut = false;
                    window.screenState.qsd = false;
                }
            }
        }
    }
}
