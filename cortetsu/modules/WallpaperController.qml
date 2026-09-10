pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "OverlayPolicy.js" as OverlayPolicy

Scope {
    id: root

    function anyOpen(): bool {
        for (const screen of CortetsuScreens.screens) {
            if (CortetsuShellState.forScreen(screen)?.cortetsuState?.wallpaperManager)
                return true;
        }
        return false;
    }

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained("wallpaperManager", false);
        }
    }

    function closeOtherPanels(): void {
        for (const screen of CortetsuScreens.screens)
            OverlayPolicy.closeForWallpaper(CortetsuShellState.forScreen(screen)?.cortetsuState?.legacyState);
    }

    function open(screen): void {
        const target = screen ?? CortetsuScreens.screens.find(candidate =>
            CortetsuHypr.monitorFor(candidate) === CortetsuHypr.focusedMonitor);
        const state = CortetsuShellState.forScreen(target)?.cortetsuState;
        if (!state)
            return;
        closeAll();
        closeOtherPanels();
        state.setRetained("wallpaperManager", true);
    }

    function openActive(): void {
        open(undefined);
    }

    function close(): void { closeAll(); }
    function toggle(): void { anyOpen() ? closeAll() : openActive(); }

    CortetsuShortcut {
        name: "wallpapermanager"
        description: "Toggle native wallpaper manager"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "wallpapermanager"
        function toggle(): void { root.toggle(); }
        function open(): void { root.openActive(); }
        function close(): void { root.close(); }
        function isOpen(): bool { return root.anyOpen(); }
    }
}
