pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../bar" as Bar
import ".."

Region {
    id: root

    required property Bar.BarWrapper bar
    required property Panels panels
    required property var win

    readonly property real borderThickness: CortetsuConfig.borderThickness
    readonly property real clampedThickness: CortetsuConfig.borderThickness

    x: bar.clampedWidth + win.dragMaskPadding
    y: clampedThickness + win.dragMaskPadding
    width: win.width - bar.clampedWidth - clampedThickness - win.dragMaskPadding * 2
    height: win.height - clampedThickness * 2 - win.dragMaskPadding * 2
    intersection: Intersection.Xor

    R {
        panel: root.panels.dashboard
        y: 0
        height: (panel?.height ?? 0) * (1 - (root.panels.dashboard?.offsetScale ?? 1)) + root.borderThickness
    }

    R {
        panel: root.panels.launcher
        y: root.win.height - height - (panel?.dockOffset ?? 0)
        height: (panel?.height ?? 0) * (1 - (root.panels.launcher?.offsetScale ?? 1)) + root.borderThickness
    }

    R {
        id: sessionRegion
        panel: root.panels.sessionWrapper
        x: root.win.width - width
        width: (panel?.width ?? 0) * (1 - (root.panels.session?.offsetScale ?? 1)) + root.borderThickness + sidebarRegion.width
    }

    R {
        id: sidebarRegion
        panel: root.panels.sidebar
        x: root.win.width - width
        width: (panel?.width ?? 0) * (1 - (root.panels.sidebar?.offsetScale ?? 1)) + root.borderThickness
    }

    R {
        panel: root.panels.osdWrapper
        x: root.win.width - width
        width: (panel?.width ?? 0) * (1 - (root.panels.osd?.offsetScale ?? 1)) + root.borderThickness + sessionRegion.width
    }

    R {
        panel: root.panels.notifications
        y: 0
        height: (panel?.height ?? 0) + root.borderThickness
    }

    R {
        panel: root.panels.utilities
        height: (panel?.height ?? 0) * (1 - (root.panels.utilities?.offsetScale ?? 1)) + root.borderThickness
    }

    R {
        panel: root.panels.popoutsWrapper
        width: (panel?.width ?? 0) * (1 - (root.panels.popoutsWrapper?.offsetScale ?? 1))
    }

    component R: Region {
        // Panel aliases become null briefly while the drawer graph is being
        // constructed or torn down. An empty subtracting region is correct
        // during that interval and avoids invalid mask geometry.
        property Item panel: null
        x: (panel?.x ?? 0) + root.bar.implicitWidth
        y: (panel?.y ?? 0) + root.borderThickness
        width: panel?.width ?? 0
        height: panel?.height ?? 0
        intersection: Intersection.Subtract
    }
}
