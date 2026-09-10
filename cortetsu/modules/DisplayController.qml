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
            if (state?.displayManager)
                return true;
        }
        return false;
    }

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained("displayManager", false);
        }
    }

    function closeOtherPanels(): void {
        for (const screen of CortetsuScreens.screens)
            OverlayPolicy.closeOtherPanels(CortetsuShellState.forScreen(screen)?.cortetsuState);
    }

    function open(screen): void {
        const target = screen ?? CortetsuScreens.screens.find(candidate =>
            CortetsuHypr.monitorFor(candidate) === CortetsuHypr.focusedMonitor);
        const state = CortetsuShellState.forScreen(target)?.cortetsuState;
        if (!state)
            return;
        closeAll();
        closeOtherPanels();
        state.setRetained("displayManager", true);
    }

    function openActive(): void {
        open(undefined);
    }

    function close(): void {
        closeAll();
    }

    function toggle(): void {
        if (anyOpen()) {
            closeAll();
            return;
        }
        openActive();
    }

    CortetsuShortcut {
        name: "displaymanager"
        description: "Toggle Cortetsu Display Manager"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "display"
        function toggle(): void { root.toggle(); }
        function open(): void { root.openActive(); }
        function close(): void { root.close(); }
        function isOpen(): bool { return root.anyOpen(); }
    }
}
