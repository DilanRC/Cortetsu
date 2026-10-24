pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "hardware/Navigation.js" as HardwareNavigation

// Hardware Center: global shortcuts "hardware", "hardwareKey" and
// "hardwareSystem", IPC target "hardware".
RetainedSurfaceController {
    id: root

    surfaceKey: "hardware"
    ipcTarget: "hardware"
    shortcutName: "hardware"
    shortcutDescription: "Toggle Cortetsu Hardware Center"

    // Accidental presses of the HP keys (OMEN, Fn+Esc beside Esc) must not
    // pull a fullscreen game or video out of focus.
    function focusedHasFullscreen(): bool {
        return CortetsuHypr.focusedFullscreen;
    }

    // Opens the center on `target` (a Navigation.js page), switches to it
    // when the center shows another page, and closes it when it already
    // shows that page.
    function showPage(target: string): void {
        const page = HardwareNavigation.pages[target];
        if (page === undefined)
            return;
        const action = HardwareNavigation.pageAction(root.anyOpen(), CortetsuShellState.hardwarePage, page);
        if (action === "close") {
            root.close();
            return;
        }
        CortetsuShellState.hardwarePage = page;
        if (action === "open")
            root.openActive();
    }

    // The OMEN key (XF86Launch2) is easy to hit by accident, so it does
    // nothing over a fullscreen game or video; SUPER+H stays the explicit way.
    CortetsuShortcut {
        name: "hardwareKey"
        description: "Toggle Cortetsu Hardware Center unless a window is fullscreen"
        onPressed: {
            if (!root.focusedHasFullscreen())
                root.toggle();
        }
    }

    // Fn+Esc (KEY_FN_ESC → XF86Fn_Esc), labelled «información del sistema»
    // by HP: the Sistema page. Hyprland binds do not repeat unless asked, and
    // a second report of the same press within 400 ms is dropped.
    property real lastSystemPressMs: 0

    CortetsuShortcut {
        name: "hardwareSystem"
        description: "Show the Hardware Center system page unless a window is fullscreen"
        onPressed: {
            const now = Date.now();
            if (!HardwareNavigation.acceptPress(root.lastSystemPressMs, now, 400))
                return;
            root.lastSystemPressMs = now;
            if (!root.focusedHasFullscreen())
                root.showPage("system");
        }
    }

    IpcHandler {
        target: "hardwarePage"
        // Same as the shortcuts, without the fullscreen guard: an explicit call.
        function show(target: string): void { root.showPage(target); }
        function current(): int { return CortetsuShellState.hardwarePage; }
    }
}
