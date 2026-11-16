pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import ".."
import "../../services"

// The widgets of one monitor, on its background layer. They sample only
// while the desktop is in view (no tiled window on the monitor's active
// workspace), and they step aside while the editor shows them on this
// monitor, so nothing is drawn twice.
Item {
    id: root

    required property ShellScreen screen

    readonly property var screenState: CortetsuShellState.forScreen(screen)
    readonly property bool editing: screenState?.cortetsuState?.desktopWidgets ?? false
    readonly property bool desktopVisible: {
        const monitor = CortetsuHypr.monitorFor(root.screen);
        return monitor?.activeWorkspace?.toplevels?.values?.every(t => t.lastIpcObject?.floating) ?? true;
    }

    visible: !editing

    Repeater {
        // Ids, not entries: moving or resizing a widget updates its
        // delegate in place instead of rebuilding the layer.
        model: ScriptModel {
            values: DesktopWidgets.idsFor(root.screen?.name ?? "")
        }

        delegate: DesktopWidget {
            id: widget
            required property string modelData
            readonly property var rect: DesktopWidgets.rectOf(item, root.screen)
            item: DesktopWidgets.entry(modelData)
            live: root.desktopVisible && root.visible
            x: rect.x
            y: rect.y
        }
    }
}
