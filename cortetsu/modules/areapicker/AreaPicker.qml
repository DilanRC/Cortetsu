pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import ".."
import "../../components/containers"
import "../../components/misc"

Scope {
    id: root

    property bool active: false
    property bool freeze: false
    property bool closing: false
    property bool clipboardOnly: false
    // Set by pickRegion(): the selection is returned instead of captured.
    property var regionHandler: null

    onActiveChanged: CortetsuShellState.screenshotActive = active
    Component.onDestruction: CortetsuShellState.screenshotActive = false

    function open(freezeFrame: bool, copyToClipboard: bool): void {
        freeze = freezeFrame;
        clipboardOnly = copyToClipboard;
        closing = false;
        active = true;
    }

    function close(): void {
        closing = true;
        active = false;
        // Escape or an empty drag while picking a share region is a cancel.
        root.returnRegion(null);
    }

    // Region tab of the screen share picker: `handler` receives
    // { output, x, y, w, h } in the output's logical coordinates, or null.
    function pickRegion(handler: var): void {
        root.returnRegion(null);
        regionHandler = handler;
        open(false, false);
    }

    function returnRegion(region: var): void {
        const handler = regionHandler;
        regionHandler = null;
        if (handler)
            handler(region);
    }

    Variants {
        model: CortetsuScreens.screens

        StyledWindow {
            id: win
            required property ShellScreen modelData
            screen: modelData
            name: "area-picker"
            visible: root.active
            WlrLayershell.exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.None : WlrKeyboardFocus.Exclusive
            anchors.top: true
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            Region { id: empty }
            Picker { state: root; screen: win.modelData }
        }
    }

    IpcHandler {
        target: "picker"
        function open(): void { root.open(false, false); }
        function openFreeze(): void { root.open(true, false); }
        function openClip(): void { root.open(false, true); }
        function openFreezeClip(): void { root.open(true, true); }
    }

    CustomShortcut { name: "screenshot"; description: "Open screenshot tool"; onPressed: root.open(false, false) }
    CustomShortcut { name: "screenshotFreeze"; description: "Open screenshot tool (freeze mode)"; onPressed: root.open(true, false) }
    CustomShortcut { name: "screenshotClip"; description: "Open screenshot tool (clipboard)"; onPressed: root.open(false, true) }
    CustomShortcut { name: "screenshotFreezeClip"; description: "Open screenshot tool (freeze mode, clipboard)"; onPressed: root.open(true, true) }
}
