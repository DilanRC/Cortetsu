pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "CortetsuOverlayPolicy.js" as OverlayPolicy

// Shortcut and IPC target of one retained surface. A retained surface is one
// instance for the seat: it opens on the focused screen (or `screen`), closes
// every exclusive surface on every screen first, and a toggle from any screen
// closes it wherever it is. CortetsuOverlayPolicy holds the rules.
Scope {
    id: root

    required property string surfaceKey
    required property string ipcTarget
    required property string shortcutName
    required property string shortcutDescription

    function anyOpen(): bool {
        return OverlayPolicy.openAnywhere(CortetsuShellState.allStates(), root.surfaceKey);
    }

    function open(screen): void {
        const target = screen ? CortetsuShellState.forScreen(screen) : CortetsuShellState.forActive();
        OverlayPolicy.open(CortetsuShellState.allStates(), target, root.surfaceKey);
    }

    function openActive(): void {
        open(null);
    }

    function close(): void {
        OverlayPolicy.close(CortetsuShellState.allStates(), root.surfaceKey);
    }

    // Closing does not need a focused screen; opening does.
    function toggle(): void {
        if (anyOpen())
            close();
        else
            openActive();
    }

    CortetsuShortcut {
        name: root.shortcutName
        description: root.shortcutDescription
        onPressed: root.toggle()
    }

    IpcHandler {
        target: root.ipcTarget
        function toggle(): void { root.toggle(); }
        function open(): void { root.openActive(); }
        function close(): void { root.close(); }
        function isOpen(): bool { return root.anyOpen(); }
    }
}
