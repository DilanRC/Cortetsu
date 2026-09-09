pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import ".."
import "../../components"
import "../../components/containers"
import "../../services"
import "../bar" as Bar
import "../CortetsuDesign.js" as CortetsuDesign

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    readonly property ScreenState screenState: ShellState.forScreen(screen)

    readonly property HyprlandMonitor monitor: Hypr.monitorFor(screen)
    readonly property bool hasSpecialWorkspace: (monitor?.lastIpcObject.specialWorkspace?.name.length ?? 0) > 0
    readonly property bool hasFullscreenOnNormalWs: monitor?.activeWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false
    readonly property bool hasFullscreen: {
        if (hasSpecialWorkspace) {
            const specialName = monitor?.lastIpcObject.specialWorkspace?.name;
            if (!specialName)
                return false;
            const specialWs = Hypr.workspaces.values.find(ws => ws.name === specialName);
            return specialWs?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false;
        }
        return hasFullscreenOnNormalWs;
    }

    property real fsTransitionProg: hasFullscreen ? 1 : 0
    readonly property real sdfBorderOffset: 2 * fsTransitionProg // SDFs joins are not exact, so offset by 2px to ensure nothing shows
    readonly property real borderThickness: CortetsuOverlayConfig.border.thickness * (1 - fsTransitionProg)
    readonly property real borderRounding: CortetsuOverlayConfig.border.rounding * (1 - fsTransitionProg)
    readonly property real shadowOpacity: 0.7 * (1 - fsTransitionProg)
    readonly property real borderLayoutThickness: hasFullscreen ? 0 : CortetsuOverlayConfig.border.thickness

    property color surfaceColour: CortetsuDesign.colorSurface

    readonly property int dragMaskPadding: {
        if (focusGrab.active || panels.popouts.isDetached)
            return 0;

        if (monitor?.lastIpcObject.specialWorkspace?.name || monitor?.activeWorkspace?.lastIpcObject.windows > 0)
            return 0;

        const thresholds = [];
        for (const panel of ["dashboard", "launcher", "session", "sidebar"])
            if (CortetsuOverlayConfig[panel].enabled)
                thresholds.push(CortetsuOverlayConfig[panel].dragThreshold);
        return Math.max(...thresholds);
    }

    onHasFullscreenChanged: {
        screenState.launcher = false;
        screenState.session = false;
        screenState.dashboard = false;
        screenState.cortetsuState?.closeRetainedOverlays();
        panels.popouts.close();
    }

    name: "drawers"
    focusable: panels.popouts.hasCurrent || (screenState.cortetsuState?.requiresWindowKeyboardFocus && !screenState.launcher && !screenState.session)
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: screenState.cortetsuState?.overview ? WlrLayer.Overlay : ((fsTransitionProg > 0 && CortetsuOverlayConfig.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top)
    // Attached BottomHub popouts are mouse-owned. Giving the full-screen
    // drawer exclusive keyboard focus steals pointer hover from the trigger
    // window, which makes the shared hover controller close and reopen them.
    WlrLayershell.keyboardFocus: (panels.popouts.isDetached || panels.popouts.currentName === "wirelesspassword")
        ? WlrKeyboardFocus.Exclusive
        : (screenState.cortetsuState?.requiresWindowKeyboardFocus && !screenState.launcher && !screenState.session)
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

    mask: screenState.cortetsuState?.requiresFullInputMask ? null : (hasFullscreen ? emptyRegion : regions)

    anchors.top: true
    anchors.bottom: true
    anchors.left: true
    anchors.right: true
    Shortcut {
        sequence: "Escape"
        enabled: focusGrab.active || panels.popouts.hasCurrent
        onActivated: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.utilities = false;
            root.screenState.dashboard = false;
            root.screenState.cortetsuState?.closeRetainedOverlays();
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    Region {
        id: emptyRegion

        x: panels.notifications.x + bar.implicitWidth
        y: panels.notifications.y + root.borderThickness
        width: panels.notifications.width
        height: panels.notifications.height

        Region {
            x: root.width - width
            y: panels.osdWrapper.y + root.borderThickness
            width: panels.osdWrapper.width * (1 - panels.osd.offsetScale) + root.borderThickness
            height: panels.osd.height
        }
    }

    Regions {
        id: regions

        bar: bar
        panels: panels
        win: root
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: {
            const s = root.screenState;
            const conf = root.CortetsuOverlayConfig;
            if (panels.popouts.isDetached || panels.popouts.currentName === "wirelesspassword")
                return true;
            if (s.cortetsuState?.retainedOverlayOpen)
                return true;
            if ((s.sidebar && conf.sidebar.enabled) || (s.utilities && conf.utilities.enabled))
                return true;
            if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
                return true;
            if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
                return true;
            return false;
        }
        windows: [root]
        onCleared: {
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.utilities = false;
            root.screenState.dashboard = false;
            root.screenState.cortetsuState?.closeRetainedOverlays();
            panels.popouts.hasCurrent = false;
            bar.closeTray();
        }
    }

    Rectangle {
        anchors.fill: parent
        opacity: root.screenState.cortetsuState?.overview ? 0.58 : ((root.screenState.session && CortetsuOverlayConfig.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0)
        // Overview opacity is already applied by the item. Keeping the color
        // opaque here avoids multiplying the scrim alpha and leaking desktop
        // content through the window-card composition.
        color: CortetsuDesign.colorScrim
        Behavior on opacity { NumberAnimation { duration: CortetsuDesign.motionFastMs; easing.type: Easing.OutCubic } }
    }

    Item {
        anchors.fill: parent
        PanelBg { id: dashBg; panel: panels.dashboard; deformAmount: 0.1 }
        PanelBg { id: launcherBg; panel: panels.launcher; deformAmount: 0.1 }
        PanelBg {
            id: sessionBg
            panel: panels.sessionWrapper
            x: panels.sessionWrapper.x + panels.session.x + bar.implicitWidth
            width: panels.session.width
            deformAmount: 0.2
        }
        PanelBg { id: sidebarBg; panel: panels.sidebar; deformAmount: 0.03 }
        PanelBg {
            id: osdBg
            panel: panels.osdWrapper
            x: panels.osdWrapper.x + panels.osd.x + bar.implicitWidth
            width: panels.osd.width
            deformAmount: 0.25
        }
        PanelBg { id: notifsBg; panel: panels.notifications }
        PanelBg { id: utilsBg; panel: panels.utilities; deformAmount: 0.12 }
        PanelBg {
            id: popoutBg
            panel: panels.popoutsWrapper
            x: panels.popoutsWrapper.x + panels.popouts.x + bar.implicitWidth
            width: panels.popouts.width
            deformAmount: panels.popouts.isDetached ? 0.05 : 0.15
        }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
        qsd: null
        bar: bar
        borderThickness: root.borderLayoutThickness
        fullscreen: root.hasFullscreen

        Panels {
            id: panels

            screen: root.screen
            screenState: root.screenState
            bar: bar
            borderThickness: root.borderThickness


        }

        Bar.BarWrapper {
            id: bar

            anchors.top: parent.top
            anchors.bottom: parent.bottom

            screen: root.screen
            screenState: root.screenState
            popouts: panels.popouts

            fullscreen: root.hasFullscreen
        }
    }


    ShellState.ComponentRef {
        screen: root.screen
        slot: "rootWindow"
        component: root
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "interactionWrapper"
        component: interactions
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "bar"
        component: bar
    }

    ShellState.ComponentRef {
        screen: root.screen
        slot: "panels"
        component: panels
    }

    component PanelBg: Rectangle {
        required property Item panel
        property real deformAmount: 0.15
        visible: panel.visible && panel.width > 0 && panel.height > 0 && (panel.offsetScale ?? 0) < 1
        x: panel.x + bar.implicitWidth
        y: panel.y + root.borderThickness
        width: panel.width
        height: panel.height
        radius: root.borderRounding
        color: Qt.alpha(root.surfaceColour, Math.max(0, 1 - (panel.offsetScale ?? 0)))
        border.width: root.borderThickness
        border.color: CortetsuDesign.colorOutlineVariant
    }
}
