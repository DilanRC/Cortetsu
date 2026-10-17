pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "OverlayPolicy.js" as OverlayPolicy
import "CortetsuFullscreen.js" as Fullscreen

Scope {
    id: root

    function anyOpen(): bool {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state?.hardware)
                return true;
        }
        return false;
    }

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained("hardware", false);
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
        state.setRetained("hardware", true);
    }

    function close(): void {
        closeAll();
    }

    function toggle(): void {
        if (anyOpen()) {
            closeAll();
            return;
        }
        open();
    }

    CortetsuShortcut {
        name: "hardware"
        description: "Toggle Cortetsu Hardware Center"
        onPressed: root.toggle()
    }

    // The OMEN key (XF86Launch2) is easy to hit by accident, so it does
    // nothing over a fullscreen game or video; SUPER+H stays the explicit way.
    CortetsuShortcut {
        name: "hardwareKey"
        description: "Toggle Cortetsu Hardware Center unless a window is fullscreen"
        onPressed: {
            const monitors = CortetsuHypr.monitors.values.map(monitor => ({
                focused: monitor?.focused,
                activeWorkspace: { toplevels: monitor?.activeWorkspace?.toplevels?.values?.map(toplevel => toplevel.lastIpcObject) ?? [] }
            }));
            if (!Fullscreen.focusedHasFullscreen(monitors))
                root.toggle();
        }
    }

    IpcHandler {
        target: "hardware"

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
