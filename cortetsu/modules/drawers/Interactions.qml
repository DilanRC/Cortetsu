import QtQuick
import QtQuick.Controls
import Quickshell
import ".."
import "../../components"
import "../../components/controls"
import "../bar" as Bar
import "../bar/popouts" as BarPopouts

CustomMouseArea {
    id: root

    required property ShellScreen screen
    required property BarPopouts.Wrapper popouts
    required property ScreenState screenState
    required property Panels panels
    property var qsd: null
    required property Bar.BarWrapper bar
    required property real borderThickness
    required property bool fullscreen

    property point dragStart
    property bool dashboardShortcutActive
    property bool osdShortcutActive
    property bool utilitiesShortcutActive
    property bool qsdShortcutActive
    property bool qsdEdgePending

    Timer {
        id: qsdOpenTimer
        interval: 180
        onTriggered: {
            if (!root.pressed && root.qsdEdgePending && !root.fullscreen)
                root.screenState.qsd = true;
        }
    }

    function withinPanelHeight(panel: Item, x: real, y: real): bool {
        const panelY = root.borderThickness + panel.y;
        return y >= panelY - CortetsuOverlayConfig.border.rounding && y <= panelY + panel.height + CortetsuOverlayConfig.border.rounding;
    }

    function withinPanelWidth(panel: Item, x: real, y: real): bool {
        const panelX = bar.implicitWidth + panel.x;
        return x >= panelX - CortetsuOverlayConfig.border.rounding && x <= panelX + panel.width + CortetsuOverlayConfig.border.rounding;
    }

    function inLeftPanel(panel: Item, x: real, y: real): bool {
        return x < bar.implicitWidth + panel.x + panel.width && withinPanelHeight(panel, x, y);
    }

    function inRightPanel(panel: Item, x: real, y: real): bool {
        return x > Math.min(width - CortetsuOverlayConfig.border.minThickness, bar.implicitWidth + panel.x) && withinPanelHeight(panel, x, y);
    }

    function inTopPanel(panel: Item, x: real, y: real): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y < Math.max(CortetsuOverlayConfig.border.minThickness, CortetsuOverlayConfig.border.thickness + panelHeight) && withinPanelWidth(panel, x, y);
    }

    function inBottomPanel(panel: Item, x: real, y: real, isCorner = false): bool {
        const panelHeight = panel.height * (1 - (panel.offsetScale ?? 0)); // qmllint disable missing-property
        return y > height - Math.max(CortetsuOverlayConfig.border.minThickness, CortetsuOverlayConfig.border.thickness + panelHeight) - (isCorner ? CortetsuOverlayConfig.border.rounding : 0) && withinPanelWidth(panel, x, y);
    }

    function insidePanel(panel: Item, x: real, y: real): bool {
        const panelX = bar.implicitWidth + panel.x;
        const panelY = root.borderThickness + panel.y;
        return x >= panelX && x <= panelX + panel.width
            && y >= panelY && y <= panelY + panel.height;
    }

    function onWheel(event: WheelEvent): void {
        if (fullscreen)
            return;
        if (event.x < bar.implicitWidth) {
            bar.handleWheel(event.y, event.angleDelta);
        }
    }

    anchors.fill: parent
    acceptedButtons: fullscreen ? Qt.NoButton : Qt.AllButtons
    hoverEnabled: true

    onPressed: event => dragStart = Qt.point(event.x, event.y)
    onContainsMouseChanged: {
        if (!containsMouse) {
            root.screenState.qsdEdgeHovered = false;
            // Only hide if not activated by shortcut
            if (!osdShortcutActive) {
                screenState.osd = false;
                root.panels.osd.hovered = false;
            }

            if (!dashboardShortcutActive)
                screenState.dashboard = false;

            if (!utilitiesShortcutActive)
                screenState.utilities = false;

            // An attached BottomHub popout is owned by the trigger window
            // until the shared hover controller closes it. Losing the full
            // drawer window's pointer must not cancel that handoff.
            if (!popouts.bottomAttached
                    && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1)) {
                popouts.hasCurrent = false;
                popouts.bottomAttached = false;
                bar.closeTray();
            }

            if (CortetsuOverlayConfig.bar.showOnHover)
                bar.isHovered = false;

            if (false && CortetsuOverlayConfig.sidebar.showOnHover)
                screenState.sidebar = false;
        }
    }

    onPositionChanged: event => {
        if (popouts.isDetached)
            return;

        const x = event.x;
        const y = event.y;
        const dragX = x - dragStart.x;
        const dragY = y - dragStart.y;

        root.qsdEdgePending = x >= width - 6;
        root.screenState.qsdEdgeHovered = root.qsdEdgePending;
        if (root.qsdEdgePending && !root.pressed && !root.screenState.qsd)
            qsdOpenTimer.restart();
        else if (!root.qsdEdgePending)
            qsdOpenTimer.stop();

        if (fullscreen) {
            root.panels.osd.hovered = inRightPanel(panels.osdWrapper, x, y);
            return;
        }

        // Show bar in non-exclusive mode on hover
        if (screenState && !screenState.bar && CortetsuOverlayConfig.bar.showOnHover && x < bar.clampedWidth)
            bar.isHovered = true;

        // Show/hide bar on drag
        if (pressed && dragStart.x < bar.clampedWidth) {
            if (dragX > CortetsuOverlayConfig.bar.dragThreshold)
                screenState.bar = true;
            else if (dragX < -CortetsuOverlayConfig.bar.dragThreshold)
                screenState.bar = false;
        }

        if (panels.sidebar.offsetScale === 1) {
            // Show osd on hover
            const showOsd = inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            const showSidebar = false;

            // Show sidebar on hover (top-right corner, bounded by notification panel height)
            if (false && CortetsuOverlayConfig.sidebar.showOnHover) {
                const sidebarTriggerY = Math.max(CortetsuOverlayConfig.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = x > Math.min(width - CortetsuOverlayConfig.border.minThickness, bar.implicitWidth + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar)
                    screenState.sidebar = true;
            }

            // Show/hide session on drag
            if (pressed && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -CortetsuOverlayConfig.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > CortetsuOverlayConfig.session.dragThreshold)
                    screenState.session = false;

                // Show sidebar on drag if in session area and session is nearly fully visible
                if (showSidebar && panels.session.offsetScale <= 0 && dragX < -CortetsuOverlayConfig.sidebar.dragThreshold)
                    screenState.sidebar = true;
            } else if (showSidebar && dragX < -CortetsuOverlayConfig.sidebar.dragThreshold) {
                // Show sidebar on drag if not in session area
                screenState.sidebar = true;
            }
        } else {
            const outOfSidebar = x < width - panels.sidebar.width * (1 - panels.sidebar.offsetScale);
            // Show osd on hover
            const showOsd = outOfSidebar && inRightPanel(panels.osdWrapper, x, y);

            // Always update visibility based on hover if not in shortcut mode
            if (!osdShortcutActive) {
                screenState.osd = showOsd;
                root.panels.osd.hovered = showOsd;
            } else if (showOsd) {
                // If hovering over OSD area while in shortcut mode, transition to hover control
                osdShortcutActive = false;
                root.panels.osd.hovered = true;
            }

            // Show/hide session on drag
            if (pressed && outOfSidebar && inRightPanel(panels.sessionWrapper, dragStart.x, dragStart.y) && withinPanelHeight(panels.sessionWrapper, x, y)) {
                if (dragX < -CortetsuOverlayConfig.session.dragThreshold)
                    screenState.session = true;
                else if (dragX > CortetsuOverlayConfig.session.dragThreshold)
                    screenState.session = false;
            }

            // Show/hide sidebar on hover
            if (false && CortetsuOverlayConfig.sidebar.showOnHover && !pressed) {
                const sidebarTriggerY = Math.max(CortetsuOverlayConfig.sidebar.minHoverThreshold, panels.notifications.y + panels.notifications.height + borderThickness);
                const showSidebarHover = x > Math.min(width - CortetsuOverlayConfig.border.minThickness, bar.implicitWidth + panels.sidebar.x) && y <= sidebarTriggerY;
                if (showSidebarHover && !screenState.sidebar) {
                    screenState.sidebar = true;
                } else {
                    const inSidebarArea = inRightPanel(panels.sidebar, x, y) || inRightPanel(panels.sessionWrapper, x, y);
                    if (!inSidebarArea)
                        screenState.sidebar = false;
                }
            }

            // Hide sidebar on drag
            if (false && pressed && inRightPanel(panels.sidebar, dragStart.x, 0) && dragX > CortetsuOverlayConfig.sidebar.dragThreshold)
                screenState.sidebar = false;
        }

        // Show launcher on hover, or show/hide on drag if hover is disabled
        if (CortetsuOverlayConfig.launcher.showOnHover) {
            if (!screenState.launcher && inBottomPanel(panels.launcher, x, y))
                screenState.launcher = true;
        } else if (pressed && inBottomPanel(panels.launcher, dragStart.x, dragStart.y) && withinPanelWidth(panels.launcher, x, y)) {
            if (dragY < -CortetsuOverlayConfig.launcher.dragThreshold)
                screenState.launcher = true;
            else if (dragY > CortetsuOverlayConfig.launcher.dragThreshold)
                screenState.launcher = false;
        }

        // Show dashboard on hover
        const showDashboard = CortetsuOverlayConfig.dashboard.showOnHover && inTopPanel(panels.dashboard, x, y);

        // Always update visibility based on hover if not in shortcut mode
        if (!dashboardShortcutActive) {
            screenState.dashboard = showDashboard;
        } else if (showDashboard) {
            // If hovering over dashboard area while in shortcut mode, transition to hover control
            dashboardShortcutActive = false;
        }

        // Show/hide dashboard on drag (for touchscreen devices)
        if (pressed && inTopPanel(panels.dashboard, dragStart.x, dragStart.y) && withinPanelWidth(panels.dashboard, x, y)) {
            if (dragY > CortetsuOverlayConfig.dashboard.dragThreshold)
                screenState.dashboard = true;
            else if (dragY < -CortetsuOverlayConfig.dashboard.dragThreshold)
                screenState.dashboard = false;
        }

        // Show popouts on hover
        if (x < bar.implicitWidth) {
            bar.checkPopout(y);
        } else if (!popouts.bottomAttached && (!popouts.currentName.startsWith("traymenu") || ((popouts.current as StackView)?.depth ?? 0) <= 1) && !inLeftPanel(panels.popoutsWrapper, x, y)) {
            popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    // Monitor individual visibility changes
    Connections {
        function onLauncherChanged() {
            // If launcher is hidden, clear shortcut flags for dashboard and OSD
            if (!root.screenState.launcher) {
                root.dashboardShortcutActive = false;
                root.osdShortcutActive = false;
                root.utilitiesShortcutActive = false;

                // Also hide dashboard and OSD if they're not being hovered
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);

                if (!inDashboardArea) {
                    root.screenState.dashboard = false;
                }
                if (!inOsdArea) {
                    root.screenState.osd = false;
                    root.panels.osd.hovered = false;
                }
            }
        }

        function onDashboardChanged() {
            if (root.screenState.dashboard) {
                // Dashboard became visible, immediately check if this should be shortcut mode
                const inDashboardArea = root.inTopPanel(root.panels.dashboard, root.mouseX, root.mouseY);
                if (!inDashboardArea) {
                    root.dashboardShortcutActive = true;
                }
            } else {
                // Dashboard hidden, clear shortcut flag
                root.dashboardShortcutActive = false;
            }
        }

        function onOsdChanged() {
            if (root.screenState.osd) {
                // OSD became visible, immediately check if this should be shortcut mode
                const inOsdArea = root.inRightPanel(root.panels.osdWrapper, root.mouseX, root.mouseY);
                if (!inOsdArea) {
                    root.osdShortcutActive = true;
                }
            } else {
                // OSD hidden, clear shortcut flag
                root.osdShortcutActive = false;
            }
        }

        function onUtilitiesChanged() {
            if (root.screenState.utilities) {
                // Utilities became visible, immediately check if this should be shortcut mode
                const inUtilitiesArea = root.inBottomPanel(root.panels.utilities, root.mouseX, root.mouseY);
                if (!inUtilitiesArea) {
                    root.utilitiesShortcutActive = true;
                }
            } else {
                // Utilities hidden, clear shortcut flag
                root.utilitiesShortcutActive = false;
            }
        }

        function onQsdChanged() {
            if (root.screenState.qsd) {
                root.qsdShortcutActive = !(root.qsd?.hovered ?? false);
            } else {
                root.qsdShortcutActive = false;
            }
        }

        target: root.screenState
    }
}
