pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import ".."
import "../../components/containers"
import "../../theme"

// Overlay window for ScreenSharePanel on the focused screen. The host owns
// the scrim, Escape and outside-click cancel and the exclusive keyboard.
PanelWindow {
    id: win

    required property var controller

    readonly property bool shown: controller.choosing
    readonly property var focusedScreen: CortetsuScreens.screens.find(
        s => CortetsuHypr.monitorFor(s) === CortetsuHypr.focusedMonitor) ?? CortetsuScreens.screens[0] ?? null

    // The window is created per request (LazyLoader); flipping this on the
    // next frame lets CortetsuPopupHost play its entry instead of popping in.
    property bool entered: false
    Component.onCompleted: Qt.callLater(() => win.entered = true)

    screen: win.focusedScreen
    visible: win.shown
    color: "transparent"
    WlrLayershell.namespace: "cortetsu-share-picker"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true

    CortetsuPopupHost {
        id: host
        open: win.shown && win.entered
        keyboardFocus: WlrKeyboardFocus.Exclusive
        onClosed: win.controller.cancel()

        ScreenSharePanel {
            controller: win.controller
            focus: true
            maxWidth: win.width
            maxHeight: win.height
            onCancelRequested: host.close()
        }
    }
}
