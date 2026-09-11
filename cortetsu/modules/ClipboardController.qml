pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "OverlayPolicy.js" as OverlayPolicy

Scope {
    id: root

    function anyOpen(): bool {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state?.clipboard)
                return true;
        }

        return false;
    }

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained("clipboard", false);
        }
    }

    function closeOtherPanels(): void {
        for (const screen of CortetsuScreens.screens)
            OverlayPolicy.closeOtherPanels(CortetsuShellState.forScreen(screen)?.cortetsuState);
    }

    function open(): void {
        const state = CortetsuShellState.forActive()?.cortetsuState;
        if (!state)
            return;

        closeAll();
        closeOtherPanels();
        state.setRetained("clipboard", true);
    }

    function close(): void {
        closeAll();
    }

    function toggle(): void {
        // The focused surface can move to another monitor once the drawer opens.
        // Do not rely on forActive() to decide whether Clipboard is already open.
        if (anyOpen()) {
            closeAll();
            return;
        }

        open();
    }

    // qmllint disable unresolved-type
    CortetsuShortcut {
        // qmllint enable unresolved-type
        name: "clipboard"
        description: "Toggle native clipboard manager"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.toggle();
        }

        function open(): void {
            root.open();
        }

        function close(): void {
            root.close();
        }

        function isOpen(): bool {
            return root.anyOpen();
        }
    }
}
