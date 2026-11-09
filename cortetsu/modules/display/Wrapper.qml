pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../settings"
import "../CortetsuOverlayPolicy.js" as OverlayPolicy

// The display manager lives in Settings → Sistema → Pantalla. This keeps the
// "displayManager" surface (SUPER+SHIFT+O, `qs ipc call display`, the launcher)
// working: opening it opens Settings on that page on the same screen.
Item {
    id: root

    required property ShellScreen screen
    required property var screenState

    readonly property bool shouldBeActive: screenState?.cortetsuState?.displayManager ?? false

    visible: false

    onShouldBeActiveChanged: {
        if (!shouldBeActive)
            return;
        screenState.cortetsuState?.setRetained("displayManager", false);
        SettingsController.select("display");
        Qt.callLater(() => OverlayPolicy.open(CortetsuShellState.allStates(), root.screenState, "settings"));
    }
}
