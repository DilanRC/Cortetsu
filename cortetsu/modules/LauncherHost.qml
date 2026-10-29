pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../components/containers"
import "../services"
import "."
import "drawers"
import "CortetsuOverlayPolicy.js" as SurfacePolicy
import "launcher"
import "../theme"

Scope {
    Variants {
        model: CortetsuScreens.screens
        StyledWindow {
            id: window
            required property ShellScreen modelData
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property bool preview: SurfacePolicy.isPreview(screenState, "launcher")
            readonly property string keyboardFocusPolicyName: screenState?.launcher
                ? (preview ? "none" : "exclusive") : "none"
            screen: modelData
            name: "launcher"
            // Mapped only while open: an idle full-screen Overlay layer keeps a
            // fullscreen game from being the monitor's solitary client.
            visible: screenState?.launcher ?? false
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: screenState?.launcher && !preview
                ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            mask: window.screenState?.launcher ? null : emptyRegion
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: emptyRegion }

            // Same policy as the retained surfaces: a click inside this
            // window but outside the panel dismisses it.
            MouseArea {
                anchors.fill: parent
                enabled: window.screenState?.launcher ?? false
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                onPressed: mouse => {
                    const inside = mouse.x >= launcher.x && mouse.x < launcher.x + launcher.width
                        && mouse.y >= launcher.y && mouse.y < launcher.y + launcher.height;
                    const hub = window.screenState?.cortetsuState?.bottomHub;
                    if (!inside && (hub?.launcherButtonContains(mouse.x, mouse.y) ?? false))
                        hub.activateLauncher();
                    else if (!inside)
                        SurfacePolicy.closeOn(window.screenState, "launcher");
                }
            }

            Content {
                id: launcher
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: window.screenState?.launcher ?? false
                screenState: window.screenState
                panels: null
                maxHeight: parent.height * 0.72

                // Opened from a key: a short fade, nothing moves. The window
                // unmaps on close, so there is no exit to animate.
                NumberAnimation on opacity {
                    id: openFade
                    running: false
                    from: 0
                    to: 1
                    duration: CortetsuDesign.motionSummonMs
                    easing.type: Easing.OutCubic
                }
            }
            HoverPreviewTracker {
                hostWindow: window
                screen: window.modelData
                screenState: window.screenState
                surface: "launcher"
                panel: launcher
                previewTriggerContains: (x, y) => CortetsuShellState.componentsFor(window.modelData)
                    ?.interactionWrapper?.previewTriggerContains("launcher", x, y) ?? false
                additionalTriggerContains: (x, y) => window.screenState?.cortetsuState?.bottomHub
                    ?.launcherButtonContains(x, y) ?? false
            }
            Connections {
                target: window.screenState
                function onLauncherChanged(): void {
                    if (!window.screenState.launcher)
                        return;
                    if (window.preview)
                        return;
                    window.focusExplicitLauncherLater();
                }
            }
            Connections {
                target: window.screenState?.cortetsuState ?? null
                function onOpenCausesChanged(): void {
                    if (window.screenState?.launcher && !window.preview)
                        window.focusExplicitLauncherLater();
                }
            }
            function focusExplicitLauncherLater(): void {
                Qt.callLater(() => {
                    if (!window.screenState?.launcher || window.preview)
                        return;
                    // Whatever path opened it (shortcut, IPC, hover, showall),
                    // no other screen keeps a launcher holding the keyboard.
                    CortetsuShellState.closeLaunchers(window.screenState);
                    openFade.restart();
                    launcher.focusSearch();
                });
            }
            Binding {
                target: window.screenState?.cortetsuState ?? null
                property: "launcherWindow"
                value: window
                when: !!window.screenState?.cortetsuState
            }
            Shortcut {
                sequence: "Escape"
                enabled: window.screenState?.launcher ?? false
                onActivated: SurfacePolicy.closeOn(window.screenState, "launcher")
            }
        }
    }
}
