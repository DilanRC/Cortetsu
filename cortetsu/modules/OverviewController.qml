pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "OverlayPolicy.js" as OverlayPolicy

Scope {
    id: root

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained("overview", false);
        }
    }

    function closeOtherPanels(): void {
        for (const screen of CortetsuScreens.screens)
            OverlayPolicy.closeOtherPanels(CortetsuShellState.forScreen(screen)?.cortetsuState);
    }

    function closeAllPopouts(): void {
        for (const screen of CortetsuScreens.screens) {
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (popouts)
                popouts.close();
        }
    }

    function open(): void {
        const state = CortetsuShellState.forActive()?.cortetsuState;
        if (!state)
            return;

        closeAll();
        closeOtherPanels();
        closeAllPopouts();
        state.setRetained("overview", true);
    }

    function close(): void {
        closeAll();
    }

    function toggle(): void {
        const state = CortetsuShellState.forActive()?.cortetsuState;
        if (!state)
            return;

        if (state.overview) {
            closeAll();
            return;
        }

        open();
    }

    // qmllint disable unresolved-type
    CortetsuShortcut {
        // qmllint enable unresolved-type
        name: "overview"
        description: "Toggle window overview"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "overview"

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
            const state = CortetsuShellState.forActive();
            return state?.overview ?? false;
        }
    }
}
