pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.components
import qs.components.containers
import qs.services
import qs.modules
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

            Rectangle { anchors.fill: parent; color: Qt.alpha(CortetsuDesign.colorSumi, 0.74); visible: window.screenState?.settings ?? false }
            CortetsuSurface {
                anchors.centerIn: parent
                width: Math.min(parent.width - CortetsuDesign.spacingSection * 2, 1180)
                height: Math.min(parent.height - CortetsuDesign.spacingSection * 2, 760)
                visible: window.screenState?.settings ?? false
                baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.985)
                radiusValue: CortetsuDesign.radiusSurface
                outlined: true
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
