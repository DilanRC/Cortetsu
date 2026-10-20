pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "CortetsuOverlayPolicy.js" as OverlayPolicy

// Window overview. Unlike the other retained surfaces it follows the focused
// screen: toggling it from another screen moves it there (see the stabilization
// contract), and opening it also closes Bottom Hub popouts.
Scope {
    id: root

    function closeAllPopouts(): void {
        for (const screen of CortetsuScreens.screens) {
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (popouts)
                popouts.close();
        }
    }

    function open(): void {
        const state = CortetsuShellState.forActive();
        if (!state)
            return;
        closeAllPopouts();
        OverlayPolicy.open(CortetsuShellState.allStates(), state, "overview");
    }

    function close(): void {
        OverlayPolicy.close(CortetsuShellState.allStates(), "overview");
    }

    function toggle(): void {
        const state = CortetsuShellState.forActive();
        if (!state)
            return;
        if (state.overview)
            close();
        else
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
            return CortetsuShellState.forActive()?.overview ?? false;
        }
    }
}
