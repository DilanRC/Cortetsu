pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components"
import "../components/containers"
import "../services"
import "."
import "settings"
import "CortetsuDesign.js" as CortetsuDesign

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            screen: modelData
            name: "settings"
            visible: true
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: screenState?.settings ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: window.screenState?.settings ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(CortetsuDesign.colorSumi, window.screenState?.settingsFullscreen ? 0.92 : 0.74)
                visible: window.screenState?.settings ?? false
            }

            Item {
                id: frame
                x: window.screenState?.settingsFullscreen
                    ? 0
                    : Math.round((parent.width - width) / 2)
                y: window.screenState?.settingsFullscreen
                    ? 0
                    : Math.round((parent.height - height) / 2)
                width: window.screenState?.settingsFullscreen
                    ? parent.width
                    : Math.min(parent.width - CortetsuDesign.spacingSection * 2, 1180)
                height: window.screenState?.settingsFullscreen
                    ? parent.height
                    : Math.min(parent.height - CortetsuDesign.spacingSection * 2, 760)
                visible: window.screenState?.settings ?? false

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.985)
                    radiusValue: window.screenState?.settingsFullscreen ? 0 : CortetsuDesign.radiusSurface
                    outlined: !window.screenState?.settingsFullscreen
                    Wrapper {
                        anchors.fill: parent
                        anchors.margins: CortetsuDesign.spacingSpacious
                        screenState: window.screenState
                        screen: window.modelData
                    }
                }
            }
        }
    }
}
