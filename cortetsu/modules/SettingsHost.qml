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
    readonly property var windows: windowVariants.instances

    Variants {
        id: windowVariants
        model: CortetsuScreens.screens

        FloatingWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool requestedOpen: screenState?.settings ?? false
            property bool nativeClosePending: false

            // Creating content and mapping a native window emit signals
            // synchronously. Run both after the state binding has returned,
            // and read the current intent so queued opens cannot become stale.
            function applyOpenState(): void {
                if (nativeClosePending) {
                    nativeClosePending = false;
                    window.visible = false;
                }
                if (requestedOpen) {
                    contentLoader.active = true;
                    window.visible = requestedOpen;
                    if (!requestedOpen) {
                        window.visible = false;
                        contentLoader.active = false;
                    }
                } else {
                    // Even after a WM close, set false to reset Quickshell's
                    // separate requested visibility before the next open.
                    window.visible = false;
                    contentLoader.active = false;
                }
            }
            onRequestedOpenChanged: Qt.callLater(window.applyOpenState)
            Component.onCompleted: Qt.callLater(window.applyOpenState)

            screen: modelData
            visible: false
            // Native WM closes must update the same state that opens Settings.
            onClosed: {
                nativeClosePending = true;
                if (screenState) screenState.settings = false;
                Qt.callLater(window.applyOpenState);
            }
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
                    active: false
                    focus: true
                    sourceComponent: Content {
                        screenState: window.screenState
                        screen: window.modelData
                        controller: SettingsController
                    }
                    onLoaded: {
                        const loaded = item;
                        Qt.callLater(() => {
                            if (window.requestedOpen && contentLoader.active && contentLoader.item === loaded && window.visible)
                                loaded.open();
                        });
                    }
                }
            }
        }
    }
}
