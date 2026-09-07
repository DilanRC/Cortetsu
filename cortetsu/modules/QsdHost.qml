pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import qs.modules
import "qsd"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forActive()

            screen: modelData
            name: "qsd"
            // Keep the layer surface alive; the drawer itself owns transient
            // visibility so the first open does not race layer allocation.
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: empty }

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
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }
            }

            Shortcut {
                sequence: "Escape"
                enabled: window.screenState?.qsd ?? false
                onActivated: window.screenState.qsd = false
            }
        }
    }
}
