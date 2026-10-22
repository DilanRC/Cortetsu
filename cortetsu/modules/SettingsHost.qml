pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../components"
import "../services"
import "."
import "settings"
import "../theme"

// Settings is a normal desktop window. FloatingWindow gives it real compositor
// state: it can be moved, tiled, resized and fullscreened.
Scope {
    Variants {
        model: CortetsuScreens.screens

        FloatingWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool requestedOpen: screenState?.settings ?? false

            screen: modelData
            visible: requestedOpen
            // Native WM closes must update the same state that opens Settings.
            onClosed: if (screenState) screenState.settings = false
            title: qsTr("Ajustes de Cortetsu")
            color: "transparent"
            surfaceFormat.opaque: false
            implicitWidth: 1368
            implicitHeight: 900
            minimumSize.width: 880
            minimumSize.height: 620

            CortetsuSurface {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingUnit
                baseColor: Qt.alpha(CortetsuDesign.colorTetsu, 0.985)
                radiusValue: CortetsuDesign.radiusSurface
                outlined: true

                // The content exists only while the window is open: a closed
                // Settings holds no pages, bindings or processes.
                Loader {
                    id: contentLoader
                    objectName: "settingsContentLoader"
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingSpacious
                    // Showing the native window emits visibleChanged before
                    // its binding returns. Load from intent, outside that path.
                    active: window.requestedOpen
                    focus: true
                    sourceComponent: Content {
                        screenState: window.screenState
                        screen: window.modelData
                        controller: SettingsController
                    }
                    onLoaded: {
                        const loaded = item;
                        Qt.callLater(() => {
                            if (contentLoader.active && contentLoader.item === loaded && window.visible)
                                loaded.open();
                        });
                    }
                }
            }
        }
    }
}
