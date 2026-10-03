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
