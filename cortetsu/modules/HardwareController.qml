pragma ComponentBehavior: Bound

import QtQuick
import "CortetsuFullscreen.js" as Fullscreen

// Hardware Center: global shortcuts "hardware" and "hardwareKey", IPC target "hardware".
RetainedSurfaceController {
    id: root

    surfaceKey: "hardware"
    ipcTarget: "hardware"
    shortcutName: "hardware"
    shortcutDescription: "Toggle Cortetsu Hardware Center"

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
}
