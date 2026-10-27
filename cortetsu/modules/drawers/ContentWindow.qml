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
import "../../theme"

StyledWindow {
    id: root

    readonly property alias bar: bar
    readonly property alias interactionWrapper: interactions

    // The shared drawer reads the same monitor-local registry as every
    // first-party host. ShellState remains available below only for legacy
    // component slots, not as a second effective state lookup.
    readonly property ScreenState screenState: CortetsuShellState.forScreen(screen)

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
        const state = screenState;
        if (!state)
            return;
        state.launcher = false;
        state.session = false;
        state.dashboard = false;
        state.cortetsuState?.closeRetainedOverlays();
        panels.popouts.close();
    }

    // Over a fullscreen window this is an Overlay layer. Once the border has
    // faded out and none of its panels shows, unmap it: an idle Overlay layer
    // keeps the fullscreen client from being the monitor's solitary client.
    // A notification, the OSD or any opened panel maps it again.
    readonly property bool hasVisibleContent: panels.notifications.visible || panels.osd.visible
        || panels.popouts.hasCurrent || panels.popouts.detachedMode !== ""
        || panels.utilities.visible || panels.sidebar.visible || focusGrab.active
        || (screenState?.cortetsuState?.overview ?? false)
    visible: fsTransitionProg < 1 || hasVisibleContent

    name: "drawers"
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: screenState?.cortetsuState?.overview ? WlrLayer.Overlay : ((fsTransitionProg > 0 && CortetsuOverlayConfig.general.showOverFullscreen) || (hasSpecialWorkspace && hasFullscreenOnNormalWs) ? WlrLayer.Overlay : WlrLayer.Top)
    // The one writer of this window's keyboard mode (`focusable` writes the
    // same Quickshell property, so it is not bound as well).
    // Attached BottomHub popouts are mouse-owned. Giving the full-screen
    // drawer exclusive keyboard focus steals pointer hover from the trigger
    // window, which makes the shared hover controller close and reopen them.
    // While the focus grab is wanted the window stays OnDemand: Hyprland drops
    // a live grab when a layer of this client that holds the keyboard switches
    // to `none` (LayerSurface::onCommit -> refocusLastWindow), which closed the
    // sidebar when it opened in the same transition that closed a retained
    // surface (O-3).
    WlrLayershell.keyboardFocus: (panels.popouts.isDetached || panels.popouts.currentName === "wirelesspassword")
        ? WlrKeyboardFocus.Exclusive
        : (panels.popouts.hasCurrent || wantsFocusGrab
           || (screenState?.cortetsuState?.requiresWindowKeyboardFocus && !(screenState?.launcher ?? false) && !(screenState?.session ?? false)))
            ? WlrKeyboardFocus.OnDemand
            : WlrKeyboardFocus.None

    mask: screenState?.cortetsuState?.requiresFullInputMask ? null : (hasFullscreen ? emptyRegion : regions)

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
            panels.popouts.close();
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

    // Panels that close on a click outside, through the focus grab below.
    readonly property bool wantsFocusGrab: {
        const s = root.screenState;
        if (!s)
            return false;
        const conf = root.CortetsuOverlayConfig;
        if (panels.popouts.isDetached || panels.popouts.currentName === "wirelesspassword")
            return true;
        if (s.cortetsuState?.retainedOverlayOpen)
            return false;
        if ((s.sidebar && conf.sidebar.enabled) || (s.utilities && conf.utilities.enabled))
            return true;
        if (!conf.dashboard.showOnHover && s.dashboard && conf.dashboard.enabled)
            return true;
        if (panels.popouts.currentName.startsWith("traymenu") && (panels.popouts.current as StackView)?.depth > 1)
            return true;
        return false;
    }

    HyprlandFocusGrab {
        id: focusGrab

        active: root.wantsFocusGrab
        windows: [root]
        onCleared: {
            if (root.screenState.sidebar)
                root.screenState.sidebarGrabClearedAt = Date.now();
            root.screenState.launcher = false;
            root.screenState.session = false;
            root.screenState.sidebar = false;
            root.screenState.utilities = false;
            root.screenState.dashboard = false;
            root.screenState.cortetsuState?.closeRetainedOverlays();
            panels.popouts.close();
            bar.closeTray();
        }
    }

    Binding {
        target: root.screenState?.cortetsuState ?? null
        property: "focusGrabRequested"
        value: root.wantsFocusGrab
    }

    Binding {
        target: root.screenState?.cortetsuState ?? null
        property: "focusGrabActive"
        value: focusGrab.active
    }

    Binding {
        target: root.screenState?.cortetsuState ?? null
        property: "fullscreenTransitionProgress"
        value: root.fsTransitionProg
    }

    Rectangle {
        anchors.fill: parent
        opacity: root.screenState?.cortetsuState?.overview ? CortetsuDesign.scrimOpacity : (((root.screenState?.session ?? false) && CortetsuOverlayConfig.session.enabled) || panels.popouts.detachedMode !== "" ? 0.5 : 0)
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
        PanelBg { id: notifsBg; panel: panels.notifications }
        PanelBg { id: utilsBg; panel: panels.utilities; deformAmount: 0.12 }
    }

    Interactions {
        id: interactions

        screen: root.screen
        popouts: panels.popouts
        screenState: root.screenState
        panels: panels
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
        // The panel graph is assembled after this background layer. Keep the
        // background empty until its alias resolves instead of dereferencing
        // a transient null panel during shell startup/shutdown.
        property Item panel: null
        property real deformAmount: 0.15
        visible: (panel?.visible ?? false) && (panel?.width ?? 0) > 0 && (panel?.height ?? 0) > 0 && (panel?.offsetScale ?? 1) < 1
        x: (panel?.x ?? 0) + bar.implicitWidth
        y: (panel?.y ?? 0) + root.borderThickness
        width: panel?.width ?? 0
        height: panel?.height ?? 0
        radius: root.borderRounding
        color: Qt.alpha(root.surfaceColour, Math.max(0, 1 - (panel?.offsetScale ?? 1)))
        border.width: root.borderThickness
        border.color: CortetsuDesign.colorOutlineVariant
    }
}
