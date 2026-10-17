pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "OverlayPolicy.js" as OverlayPolicy

// Opens one retained surface on the focused screen and closes it on every
// other: the shortcut and IPC target of a surface that has no extra policy.
Scope {
    id: root

    required property string surfaceKey
    required property string ipcTarget
    required property string shortcutName
    required property string shortcutDescription

    function anyOpen(): bool {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state?.[root.surfaceKey])
                return true;
        }
        return false;
    }

    function closeAll(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
            if (state)
                state.setRetained(root.surfaceKey, false);
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
        state.setRetained(root.surfaceKey, true);
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
