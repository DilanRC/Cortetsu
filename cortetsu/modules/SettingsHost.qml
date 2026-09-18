pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../components"
import "../services"
import "."
import "settings"
import "CortetsuDesign.js" as CortetsuDesign

// Settings is a normal desktop window. FloatingWindow gives it real compositor
// state: it can be moved, tiled, resized and fullscreened.
Scope {
    Variants {
        model: CortetsuScreens.screens

        FloatingWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)

            screen: modelData
            visible: screenState?.settings ?? false
            title: qsTr("Ajustes de Cortetsu")
            color: "transparent"
            surfaceFormat.opaque: false
            implicitWidth: 1180
            implicitHeight: 760
            minimumSize.width: 820
            minimumSize.height: 560

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
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
