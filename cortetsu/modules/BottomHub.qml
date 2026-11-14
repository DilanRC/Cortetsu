pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.SystemTray
import "../services"
import "../utils"
import "launcher/services"
import "BottomHubResolver.js" as BottomHubResolver
import "BottomHubTray.js" as BottomHubTray
import "HubAnchor.js" as HubAnchor
import "WindowPreview.js" as WindowPreview
import "CortetsuOverlayPolicy.js" as OverlayPolicy
import "OverlayPolicy.js" as Exclusion
import "utilities/toasts" as Toasts

Scope {
    id: hubRoot

    CortetsuBottomHubVisibility {
        id: visibility
        autoHideEnabled: CortetsuConfig.bar.showOnHover
    }

    readonly property bool shown: visibility.shown

    CortetsuHoverSurfaceController {
        id: hoverSurfaceController

        onOpenRequested: (screen, mode, anchorCenter) =>
            hubRoot.openAttachedControlNow(screen, mode, anchorCenter)
        onCloseRequested: hubRoot.closeAllPopouts(true)
    }

    Connections {
        target: CortetsuConfig.bar.popouts

        function onStatusIconsChanged(): void {
            if (!CortetsuConfig.bar.popouts.statusIcons) {
                hoverSurfaceController.cancelPending();
                hubRoot.closeAllPopouts();
            }
        }
    }

    Timer {
        id: hideTimer
        interval: 500
        repeat: false
        onTriggered: visibility.setShown(false)
    }

    function closeAllLaunchers(): void {
        CortetsuShellState.closeLaunchers(null);
    }

    function closeAllPanels(): void {
        OverlayPolicy.closeExclusiveEverywhere(CortetsuShellState.allStates());
    }

    // A Bottom Hub button acts on its own screen: the surface opens there
    // (closing every exclusive surface, on any screen) unless it is open there.
    function toggleSurfaceOn(screen, flag: string): bool {
        return OverlayPolicy.toggleOn(CortetsuShellState.allStates(), CortetsuShellState.forScreen(screen), flag);
    }

    // A hover close leaves a Wi-Fi password being typed alone: the pointer
    // leaving it (for another screen, say) must not drop the typed text.
    function closeAllPopouts(hover = false): void {
        for (const screen of CortetsuScreens.screens) {
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (popouts && !(hover && popouts.holdsKeyboard))
                popouts.close();
        }
    }

    function toggleClipboardFor(screen): void {
        closeAllPopouts();
        toggleSurfaceOn(screen, "clipboard");
        setShown(true);
    }

    function setShown(value): void {
        if (value) {
            hideTimer.stop();
            visibility.setShown(true);
            return;
        }

        // Let attached popouts finish their return-to-icon animation while
        // the parent panel still owns the full screen geometry.
        hideTimer.restart();
        visibility.cancelAutoHide();
        closeAllLaunchers();
        closeAllPanels();
        closeAllPopouts();
    }

    function toggle(): void {
        setShown(!shown);
    }

    // Opening the calendar requests its sync (CalendarService).
    function openCalendarFor(screen): void {
        closeAllPopouts();
        toggleSurfaceOn(screen, "calendar");
        setShown(true);
    }

    // The launcher is one effective state across screens: a toggle closes it
    // wherever it is. Launcher visibility is independent from BottomHub
    // visibility: opening it by its shortcut does not resurrect the bar.
    function toggleLauncherFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;
        const all = CortetsuShellState.allStates();
        if (CortetsuShellState.launcherOpenAnywhere()) {
            if (state.launcher && OverlayPolicy.isPreview(state, "launcher")) {
                OverlayPolicy.promotePreview(all, state, "launcher");
                return;
            }
            OverlayPolicy.close(all, "launcher");
            return;
        }
        closeAllPopouts();
        OverlayPolicy.open(all, state, "launcher");
    }

    // Notifications are a standalone surface; opening them closes every
    // exclusive surface (quick settings included) like SUPER+N does.
    // The bell's hub window is part of the drawers focus grab, so pressing it
    // does not clear the grab and close the sidebar before this toggle runs.
    function toggleSidebarFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;
        if (!state.sidebar)
            closeAllPopouts();
        toggleSurfaceOn(screen, "sidebar");
        setShown(true);
    }

    function toggleUtilitiesFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;

        closeAllPanels();
        closeAllPopouts();
        toggleSurfaceOn(screen, "osd");
        setShown(true);
    }

    function openWallpaperFor(screen): void {
        closeAllPopouts();
        WallpaperController.open(screen);
        setShown(true);
    }

    function toggleDetachedControlFor(screen, mode): void {
        const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
        if (!popouts)
            return;

        closeAllLaunchers();
        closeAllPanels();

        if (popouts.isDetached && popouts.queuedMode === mode) {
            popouts.close();
            return;
        }

        popouts.detach(mode);
        setShown(true);
    }

    function openAttachedControlNow(screen, mode, anchorCenter = -1): void {
        const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
        if (!popouts)
            return;

        // An attached popout follows the pointer and never takes the
        // keyboard, so it only clears its own screen: a surface opened on
        // another monitor stays open (F1a O-4).
        const state = CortetsuShellState.forScreen(screen);
        OverlayPolicy.closeExclusiveEverywhere(state ? [state] : []);
        // One attached control at a time: the hover controller is shared by
        // every screen, so entering the hub of another screen stops the close
        // that would have dismissed this one. Detached popouts and a Wi-Fi
        // password being typed (attached, but holding the keyboard) stay.
        for (const other of CortetsuScreens.screens) {
            const otherPopouts = CortetsuShellState.componentsFor(other)?.popouts;
            if (other !== screen && otherPopouts?.hasCurrent && otherPopouts.bottomAttached
                    && otherPopouts.currentName !== "wirelesspassword")
                otherPopouts.close();
        }
        // A hover over the menu a click already opened must not take its
        // keyboard away; any other popout starts without it.
        if (!popouts.hasCurrent || popouts.currentName !== mode)
            popouts.keyboardHeld = false;
        // Opened again while it is closing: it starts over (a tray menu at
        // its first level). Later in the fade Content.qml does the same.
        const reopening = popouts.closing && popouts.currentName === mode;
        popouts.cancelClose();
        if (reopening)
            popouts.current?.reset?.();
        popouts.detachedMode = "";
        popouts.hubAnchor = CortetsuConfig.bottomHub.anchorFor(screen.name);
        popouts.bottomAnchorCenter = anchorCenter;
        popouts.bottomAttached = true;
        popouts.currentName = mode;
        popouts.hasCurrent = true;
        setShown(true);
    }

    // The edit mode opens over everything else.
    HubEditHost {
        id: editHost
        onBegun: {
            hoverSurfaceController.cancelPending();
            hubRoot.closeAllPopouts();
            hubRoot.closeAllLaunchers();
            hubRoot.closeAllPanels();
        }
    }

    function showAttachedControlFor(screen, mode, anchorCenter = -1): void {
        hoverSurfaceController.request(screen, mode, anchorCenter);
    }

    function enterAttachedControl(screen, mode, anchorCenter = -1, dwell = -1): void {
        hoverSurfaceController.enterTrigger();
        hoverSurfaceController.request(screen, mode, anchorCenter, dwell);
    }

    IpcHandler {
        target: "bottomHub"

        function toggle(): void { hubRoot.toggle(); }
        function show(): void { hubRoot.setShown(true); }
        function hide(): void { hubRoot.setShown(false); }
        function isShown(): bool { return hubRoot.shown; }
        // Read-only: the bell of the focused screen in layout coordinates
        // ("x y width height"), so pointer tests click it like a person.
        function notificationsButton(): string {
            const state = CortetsuShellState.forActive();
            const r = state?.cortetsuState?.bottomHub?.notificationsButtonRect();
            if (!r || r.width <= 0)
                return "";
            return `${state.modelData.x + r.x} ${state.modelData.y + r.y} ${r.width} ${r.height}`;
        }
        // Read-only: the tray segment of the focused screen, same format.
        function trayButton(): string {
            const state = CortetsuShellState.forActive();
            const r = state?.cortetsuState?.bottomHub?.traySegmentRect();
            if (!r || r.width <= 0)
                return "";
            return `${state.modelData.x + r.x} ${state.modelData.y + r.y} ${r.width} ${r.height}`;
        }
        // Read-only: the App Rail of the focused screen, as
        // [{key, running, windows, pinned}], and one icon's rect.
        function apps(): string {
            const hub = CortetsuShellState.forActive()?.cortetsuState?.bottomHub;
            return JSON.stringify((hub?.dockViewItems ?? []).map(item => ({ key: item.key, running: item.running,
                windows: item.windowCount, pinned: item.pinned })));
        }
        function appButton(key: string): string {
            const state = CortetsuShellState.forActive();
            const r = state?.cortetsuState?.bottomHub?.appButtonRect(key);
            if (!r || r.width <= 0)
                return "";
            return `${state.modelData.x + r.x} ${state.modelData.y + r.y} ${r.width} ${r.height}`;
        }
        // Read-only runtime evidence for focus, lifetime and monitor ownership.
        function inspect(): string {
            return JSON.stringify(CortetsuScreens.screens.map(screen => {
                const state = CortetsuShellState.forScreen(screen);
                const panels = CortetsuShellState.componentsFor(screen);
                const popup = panels?.popouts;
                const trayLoader = popup?.content?.item?.currentPopout ?? null;
                const trayMenu = popup?.current ?? null;
                const popupWindow = panels?.popoutsWrapper ?? null;
                return { screen: screen.name, launcher: state?.launcher ?? false,
                    utilities: state?.utilities ?? false, sidebar: state?.sidebar ?? false,
                    popup: popup?.currentName ?? "", open: popup?.hasCurrent ?? false,
                    closing: popup?.closing ?? false, detached: popup?.detachedMode ?? "",
                    anchor: popup?.bottomAnchorCenter ?? -1, focus: popup?.activeFocus ?? false,
                    keyboardHeld: popup?.keyboardHeld ?? false,
                    engaged: (state?.cortetsuState?.bottomHub?.hubView?.islands ?? []).map(island => island.engaged),
                    preview: { app: WindowPreview.appKeyOf(popup?.currentName ?? ""),
                        cards: popup?.current?.cardCount ?? 0, selected: popup?.current?.selected ?? -1 },
                    hubAnchor: CortetsuConfig.bottomHub.anchorFor(screen.name),
                    popupRect: popupWindow ? [popupWindow.x + (panels?.x ?? 0), popupWindow.y + (panels?.y ?? 0),
                        popupWindow.width, popupWindow.height] : [],
                    tray: { itemKey: trayLoader?.modelData?.key ?? null,
                        popupName: trayLoader?.name ?? null,
                        shouldBeActive: trayLoader?.shouldBeActive ?? false,
                        loaderActive: trayLoader?.active ?? false,
                        menuHandle: !!trayLoader?.menuHandle,
                        stackDepth: trayMenu?.menuDepth ?? 0,
                        focusedRow: trayMenu?.focusedRow ?? -1,
                        markedRow: trayMenu?.markedRow?.() ?? -1,
                        menuContentHeight: trayMenu?.menuContentHeight ?? 0,
                        menuHeight: trayMenu?.implicitHeight ?? 0,
                        popupY: popupWindow?.y ?? 0,
                        popupHeight: popupWindow?.height ?? 0,
                        screenHeight: screen.height ?? 0 } };
            }));
        }
        function launcher(): void {
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            hubRoot.toggleLauncherFor(state.modelData);
        }
        // Where the Hub sits. `monitor` is an output name, or "" for every
        // monitor without an anchor of its own. Also the way back from a
        // Hub that ended up somewhere unusable:
        //   qs ipc call bottomHub -- anchor "" bottom-center
        function anchor(monitor: string, id: string): bool {
            if (!HubAnchor.valid(id))
                return false;
            CortetsuConfig.bottomHub.setAnchor(monitor, id);
            return true;
        }
        function clearAnchor(monitor: string): void {
            CortetsuConfig.bottomHub.clearAnchor(monitor);
        }
        // The edit mode. `monitor` "" edits the focused one.
        function editMode(monitor: string): bool {
            return HubEditState.begin(monitor.length > 0 ? monitor : (CortetsuShellState.forActive()?.modelData?.name ?? ""));
        }
        function editTarget(id: string): bool {
            HubEditState.target(id);
            return HubEditState.active && HubEditState.pending === id;
        }
        function editSave(): bool { return HubEditState.save(); }
        function editCancel(): void { HubEditState.cancel(); }
        // Read-only: the edit mode's state and the dragged shape in layout
        // coordinates ("monitor pending x y width height"), "" while closed.
        function editState(): string {
            const screen = editHost.screen;
            const ghost = editHost.window?.ghostRect;
            if (!HubEditState.active || !screen || !ghost)
                return "";
            return `${HubEditState.monitor} ${HubEditState.pending} ${screen.x + ghost.x} ${screen.y + ghost.y} ${ghost.width} ${ghost.height}`;
        }
        function anchors(): string {
            const out = {};
            for (const screen of CortetsuScreens.screens)
                out[screen.name] = CortetsuConfig.bottomHub.anchorFor(screen.name);
            return JSON.stringify(out);
        }
        // Same fullscreen guard as SUPER+N and `drawers toggle`: these do not
        // open over a fullscreen window; closing still works.
        function notifications(): void {
            const state = CortetsuShellState.forActive();
            if (CortetsuHypr.focusedFullscreen && !state?.sidebar)
                return;
            hubRoot.toggleSidebarFor(state?.modelData);
        }
        function quickSettings(): void {
            const state = CortetsuShellState.forActive();
            if (CortetsuHypr.focusedFullscreen && !state?.osd)
                return;
            hubRoot.toggleUtilitiesFor(state?.modelData);
        }
        function control(mode: string): bool {
            const allowed = ["activewindow", "audio", "network", "bluetooth", "battery", "kblayout", "lockstatus", "winfo"];
            const screen = CortetsuShellState.forActive()?.modelData;
            if (!screen || !allowed.includes(mode))
                return false;
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (!popouts)
                return false;
            if (mode === "winfo") {
                hubRoot.toggleDetachedControlFor(screen, mode);
                return true;
            }
            // A second call with the same mode closes it, and a popup opened
            // here never stays behind on another monitor.
            const wasOpen = popouts.hasCurrent && !popouts.closing && !popouts.isDetached
                && popouts.currentName === mode;
            hubRoot.closeAllPopouts();
            if (!wasOpen)
                hubRoot.showAttachedControlFor(screen, mode);
            return true;
        }
        function closeControl(): void {
            hoverSurfaceController.cancelPending();
            hubRoot.closeAllPopouts();
        }
        function detachedControl(mode: string): bool {
            const allowed = ["activewindow", "audio", "network", "bluetooth", "battery", "kblayout", "lockstatus", "winfo"];
            const screen = CortetsuShellState.forActive()?.modelData;
            if (!screen || !allowed.includes(mode))
                return false;
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (!popouts)
                return false;
            hubRoot.toggleDetachedControlFor(screen, mode);
            return true;
        }
    }

    // Compatibility with the existing SUPER+D binding and helper scripts.
    IpcHandler {
        target: "customDock"

        function toggle(): void { hubRoot.toggle(); }
        function show(): void { hubRoot.setShown(true); }
        function hide(): void { hubRoot.setShown(false); }
        function isShown(): bool { return hubRoot.shown; }
        function launcher(): void {
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            hubRoot.toggleLauncherFor(state.modelData);
        }
        // Opens the launcher in emoji mode, or closes it like launcher().
        function emoji(): void {
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            if (!CortetsuShellState.launcherOpenAnywhere())
                CortetsuShellState.launcherQuery = `${CortetsuConfig.actionPrefix}emoji `;
            hubRoot.toggleLauncherFor(state.modelData);
            // A launcher that did not open must not start in emoji mode later.
            if (!state.launcher)
                CortetsuShellState.launcherQuery = "";
        }
    }

    // Auto-hide only: each layer window costs a GL context (Exclusions.qml).
    // The edge is part of the model, so a new anchor gets a new strip: a
    // transparent surface never draws again, and its new anchors would never
    // be committed.
    Variants {
        model: visibility.autoHideEnabled
            ? CortetsuScreens.screens.map(screen => ({ screen,
                edge: HubAnchor.describe(CortetsuConfig.bottomHub.anchorFor(screen?.name ?? "")).edge }))
            : []

        HubRevealEdge {
            required property var modelData

            screen: modelData.screen
            edge: modelData.edge
            onPointerEntered: {
                hideTimer.stop();
                visibility.pointerEntered();
            }
            onPointerExited: visibility.pointerExited()
        }
    }

    Variants {
        model: CortetsuScreens.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property var monitor: CortetsuScreens.monitorFor(modelData)
            readonly property var hubView: bottomHubView
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property var cortetsuState: screenState?.cortetsuState
            readonly property bool hubShown: hubRoot.shown
            readonly property bool revealStripVisible: visibility.autoHideEnabled && !hubRoot.shown
            readonly property string keyboardFocusPolicyName: hubRoot.shown ? "on_demand" : "none"
            readonly property string activeAddress:
                CortetsuHypr.activeToplevel?.lastIpcObject?.address ?? ""
            readonly property bool panelActive:
                (screenState?.launcher ?? false)
                || (cortetsuState?.overview ?? false)
                || (screenState?.sidebar ?? false)
                || (screenState?.session ?? false)
                || (cortetsuState?.calendar ?? false)

            // A bell click opens Sidebar while the focus grab whitelists this
            // window. Keep Escape available from that keyboard target too.
            Shortcut {
                sequence: "Escape"
                enabled: win.hubShown && (win.screenState?.sidebar ?? false)
                onActivated: OverlayPolicy.closeOn(win.screenState, "sidebar")
            }

            // Attached popouts live outside the screen-state flags, so the
            // exclusivity policy closes them from here when a full surface opens.
            readonly property bool fullSurfaceOpen: Exclusion.hasCompetingPanel(screenState)
                || (cortetsuState?.wallpaperManager ?? false)
            onFullSurfaceOpenChanged: if (fullSurfaceOpen) hubRoot.closeAllPopouts()
            readonly property int hubMargin: 8
            // Where this monitor's Hub sits. An unknown or damaged value
            // reads as the bottom (HubAnchor.normalize).
            readonly property string hubAnchor: CortetsuConfig.bottomHub.anchorFor(modelData?.name ?? "")
            readonly property var hubPlace: HubAnchor.describe(hubAnchor)
            readonly property bool hubVertical: hubPlace.vertical
            readonly property int edgeMargin: 2
            // The window's origin on its screen. Layer shell centres a
            // surface along the edge it is anchored to.
            readonly property real originX: hubPlace.edge === "left" ? edgeMargin
                : hubPlace.edge === "right" ? (modelData?.width ?? 0) - edgeMargin - width
                : Math.round(((modelData?.width ?? 0) - width) / 2)
            readonly property real originY: hubPlace.edge === "top" ? edgeMargin
                : hubPlace.edge === "bottom" ? (modelData?.height ?? 0) - edgeMargin - height
                : Math.round(((modelData?.height ?? 0) - height) / 2)
            // An attached popout opens at this point along the Hub's edge,
            // in screen coordinates.
            function alongScreen(center: real): real {
                return (hubVertical ? originY + bottomHubView.y : originX + bottomHubView.x) + center;
            }
            // With auto-hide the window stays mapped while hidden, draws
            // nothing, and new anchors and size never reached the compositor:
            // the Hub came back on the old edge. Unmapped for one turn, it is
            // configured afresh.
            property bool remapping: false
            onHubAnchorChanged: {
                hubRoot.closeAllPopouts();
                if (visibility.autoHideEnabled) {
                    remapping = true;
                    Qt.callLater(() => remapping = false);
                }
            }
            readonly property int activeWsId: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
                ? monitor?.activeWorkspace?.id ?? CortetsuHypr.activeWsId
                : CortetsuHypr.activeWsId
            readonly property int workspaceCount: CortetsuConfig.workspacesShown
            readonly property int workspaceOffset: Math.floor((activeWsId - 1) / workspaceCount) * workspaceCount
            readonly property var occupiedWorkspaceIds: CortetsuHypr.workspaces.values
                .filter(ws => ws.lastIpcObject?.windows > 0)
                .map(ws => ws.id)
            readonly property var workspaceAppIconSources: CortetsuConfig.bar.workspaces.showAppIcons
                ? BottomHubResolver.workspaceAppIcons(
                CortetsuHypr.toplevels.values,
                activeAddress,
                client => CortetsuHypr.isTaskbarToplevel(client),
                client => {
                    const window = client.lastIpcObject ?? {};
                    const entry = desktopEntryForClient(client);
                    return Icons.getAppIcon(entry?.icon || window.class || window.initialClass, "image-missing");
                }
            ) : ({})

            readonly property string volumeIcon: Icons.getVolumeIcon(CortetsuAudio.volume, CortetsuAudio.muted)
            readonly property string networkIcon: CortetsuNetwork.activeEthernet
                ? "cable"
                : CortetsuNetwork.connecting
                    ? "sync"
                : CortetsuNetwork.active
                    ? Icons.getNetworkIcon(CortetsuNetwork.active.strength ?? 0)
                    : "wifi_off"
            readonly property bool networkActive: CortetsuNetwork.connecting || CortetsuNetwork.activeEthernet || !!CortetsuNetwork.active
            readonly property string networkTooltip: CortetsuNetwork.connecting
                ? qsTr("Conectando a la red")
                : CortetsuNetwork.activeEthernet
                    ? qsTr("Ethernet conectado")
                    : CortetsuNetwork.active
                        ? qsTr("%1 · señal %2% · %3").arg(CortetsuNetwork.active.ssid).arg(Math.round(CortetsuNetwork.active.strength ?? 0)).arg(Connectivity.internetLabel)
                        : qsTr("Red no disponible")
            readonly property bool bluetoothActive: Connectivity.bluetooth.connectedCount > 0
            readonly property string bluetoothIcon: bluetoothActive ? "bluetooth_connected"
                : Connectivity.bluetooth.busy ? "sync"
                : !Connectivity.bluetooth.enabled ? "bluetooth_disabled" : "bluetooth"
            readonly property bool batteryCharging: CortetsuPower.charging
            readonly property string batteryIcon: CortetsuPower.hasBattery
                ? Icons.getBatteryIcon(CortetsuPower.value, batteryCharging)
                : "balance"
            readonly property bool batteryCritical: CortetsuPower.critical
            readonly property string batteryTooltip: CortetsuPower.hasBattery
                ? qsTr("Batería %1%").arg(CortetsuPower.percent)
                : qsTr("Perfil de energía")

            property var pendingFocusClient: null

            function desktopEntryForClient(client): var {
                return BottomHubResolver.desktopEntryForWindow(
                    client.lastIpcObject ?? {},
                    Apps.applications,
                    identity => DesktopEntries.byId(identity),
                    candidate => Strings.testRegexList(CortetsuConfig.favouriteApps, candidate.id)
                );
            }

            readonly property var dockItems: {
                const clients = CortetsuHypr.toplevels.values.filter(client => {
                    if (!CortetsuHypr.isTaskbarToplevel(client))
                        return false;

                    const clientMonitor = client.lastIpcObject?.monitor;
                    return win.monitor && clientMonitor === win.monitor.id;
                });

                const groups = BottomHubResolver.groupWindows(clients, desktopEntryForClient);

                const result = [];
                const pinnedEntries = Apps.applications.filter(entry =>
                    Strings.testRegexList(CortetsuConfig.favouriteApps, entry.id)
                );

                for (const entry of pinnedEntries) {
                    const existing = groups.get(entry.id);

                    if (existing) {
                        existing.pinned = true;
                        result.push(existing);
                        groups.delete(entry.id);
                    } else {
                        result.push({
                            key: entry.id,
                            entry: entry,
                            className: entry.startupClass ?? entry.id,
                            pinned: true,
                            windows: []
                        });
                    }
                }

                for (const group of groups.values())
                    result.push(group);

                return result;
            }

            readonly property var dockViewItems: dockItems.map(item => ({
                key: item.key,
                pinned: item.pinned,
                running: item.windows.length > 0,
                active: item.windows.some(
                    client => client.lastIpcObject?.address === activeAddress
                ),
                title: item.entry?.name ?? item.className,
                iconSource: Icons.getAppIcon(item.entry?.icon || item.className, "image-missing"),
                windowCount: item.windows.length
            }))

            readonly property var trayViewItems: BottomHubTray.visibleEntries(
                SystemTray.items.values,
                CortetsuConfig.hiddenTrayIcons,
                Status.Passive
            )
                .map(({ key, item }) => ({
                    key,
                    id: item.id,
                    needsAttention: item.status === Status.NeedsAttention,
                    title: BottomHubTray.tooltipFor(item),
                    iconSource: item.icon || Icons.getTrayIcon(item.id, item.icon),
                    onlyMenu: item.onlyMenu,
                    hasMenu: item.hasMenu
                }))

            function dockItemForKey(key): var {
                return dockItems.find(item => item.key === key) ?? null;
            }

            function trayItemForKey(key): var {
                return BottomHubTray.itemForKey(SystemTray.items.values, key);
            }

            function togglePinned(item): void {
                const entry = item?.entry;
                if (!entry)
                    return;

                const id = entry.id;
                const apps = CortetsuConfig.favouriteApps;

                if (apps.includes(id)) {
                    CortetsuConfig.setFavouriteApps(apps.filter(app => app !== id));
                } else if (!Strings.testRegexList(apps, id)) {
                    CortetsuConfig.setFavouriteApps([...apps, id]);
                }
            }

            function focusWindowNow(client): void {
                if (!client)
                    return;

                const address = client.lastIpcObject?.address;
                if (!address)
                    return;

                if (!CortetsuHypr.toplevels.values.some(
                    candidate => candidate.lastIpcObject?.address === address
                ))
                    return;

                CortetsuHypr.focusWindow(address);
            }

            function focusWindow(client): void {
                if (!client)
                    return;

                pendingFocusClient = client;
                cursorPosProcess.exec(["hyprctl", "cursorpos"]);
            }

            function closeWindow(client): void {
                if (!client)
                    return;

                const address = client.lastIpcObject?.address;
                if (!address)
                    return;

                CortetsuHypr.closeWindow(address);
            }

            function activeWindowFor(item): var {
                for (const client of item.windows) {
                    if (client.lastIpcObject?.address === activeAddress)
                        return client;
                }
                return null;
            }

            function activateItem(item): void {
                if (!item.windows.length) {
                    if (item.entry)
                        Apps.launch(item.entry);
                    return;
                }

                const active = activeWindowFor(item);

                if (!active) {
                    focusWindow(item.windows[0]);
                    return;
                }

                if (item.windows.length === 1) {
                    focusWindow(active);
                    return;
                }

                const index = item.windows.indexOf(active);
                focusWindow(item.windows[(index + 1) % item.windows.length]);
            }

            function cycleItem(item, direction): void {
                if (!item.windows.length)
                    return;

                const active = activeWindowFor(item);

                if (!active) {
                    focusWindow(item.windows[0]);
                    return;
                }

                const index = item.windows.indexOf(active);
                const count = item.windows.length;
                focusWindow(item.windows[(index + direction + count) % count]);
            }

            function activateDockKey(key): void {
                const item = dockItemForKey(key);
                if (item)
                    activateItem(item);
            }

            function cycleDockKey(key, direction): void {
                const item = dockItemForKey(key);
                if (item)
                    cycleItem(item, direction);
            }

            function closeDockKey(key): void {
                const item = dockItemForKey(key);
                if (!item)
                    return;
                const active = activeWindowFor(item);
                closeWindow(active ?? item.windows[0]);
            }

            function togglePinnedKey(key): void {
                const item = dockItemForKey(key);
                if (item)
                    togglePinned(item);
            }

            function launchDockKey(key): void {
                const entry = dockItemForKey(key)?.entry;
                if (entry)
                    Apps.launch(entry);
            }

            // An app's window preview: by hover after a longer dwell than the
            // status icons (crossing the rail opens nothing), or from the
            // keyboard, which hands it the keys typed on the icon.
            readonly property int previewDwellMs: 450
            function showAppPreview(key, centerX): void {
                if (!CortetsuConfig.bottomHub.windowPreviews || !(dockItemForKey(key)?.windows.length > 0))
                    return;
                hubRoot.enterAttachedControl(modelData, WindowPreview.popoutName(key), alongScreen(centerX), previewDwellMs);
            }

            function openAppPreview(key, centerX): void {
                if (!(dockItemForKey(key)?.windows.length > 0))
                    return;
                hubRoot.openAttachedControlNow(modelData, WindowPreview.popoutName(key), alongScreen(centerX));
                const popouts = CortetsuShellState.componentsFor(modelData)?.popouts;
                if (!popouts)
                    return;
                popouts.keyboardHeld = true;
                Qt.callLater(() => popouts.current?.selectInitial?.());
            }

            function showTrayMenu(itemKey, centerX): void {
                const item = trayItemForKey(itemKey);
                if (!item || BottomHubTray.contextAction(item) !== "menu")
                    return;
                hubRoot.enterAttachedControl(
                    modelData,
                    BottomHubTray.menuName(itemKey),
                    alongScreen(centerX)
                );
            }

            function openTrayMenu(itemKey, centerX): void {
                const item = trayItemForKey(itemKey);
                if (!item || BottomHubTray.contextAction(item) !== "menu")
                    return;
                hubRoot.openAttachedControlNow(
                    modelData,
                    BottomHubTray.menuName(itemKey),
                    alongScreen(centerX)
                );
                const popouts = CortetsuShellState.componentsFor(modelData)?.popouts;
                if (popouts)
                    popouts.keyboardHeld = true;
            }

            // A tray menu opened by a click, or a window preview opened from
            // the keyboard, is driven from here: the Hub already has the
            // keyboard (OnDemand), and an attached popout's window never
            // takes it, so the keys typed on the icon are passed on to it.
            function forwardHeldKey(key, modifiers): bool {
                const popouts = CortetsuShellState.componentsFor(modelData)?.popouts;
                if (!popouts?.keyboardHeld || popouts.closing)
                    return false;
                return popouts.current?.handleKey?.(key, modifiers) ?? false;
            }

            function activateTrayItem(itemKey): void {
                const item = trayItemForKey(itemKey);
                if (!item)
                    return;
                if (BottomHubTray.primaryAction(item) === "activate")
                    item.activate();
            }

            function activateTraySecondary(itemKey): void {
                const item = trayItemForKey(itemKey);
                if (item)
                    item.secondaryActivate();
            }

            function scrollTrayItem(itemKey, delta, horizontal): void {
                const item = trayItemForKey(itemKey);
                if (item)
                    item.scroll(delta, horizontal);
            }

            // The bell in screen coordinates.
            function notificationsButtonRect(): rect {
                const bell = bottomHubView.notificationsButton;
                if (!visible || !hubRoot.shown || !bell?.visible)
                    return Qt.rect(0, 0, 0, 0);
                const p = bell.mapToItem(contentItem, 0, 0);
                return Qt.rect(originX + p.x, originY + p.y, bell.width, bell.height);
            }

            function appButtonRect(key: string): rect {
                const button = bottomHubView.appRailItem?.buttonFor(key);
                if (!visible || !hubRoot.shown || !button?.visible)
                    return Qt.rect(0, 0, 0, 0);
                const p = button.mapToItem(contentItem, 0, 0);
                return Qt.rect(originX + p.x, originY + p.y, button.width, button.height);
            }

            function traySegmentRect(): rect {
                const tray = bottomHubView.traySegmentItem;
                if (!visible || !hubRoot.shown || !tray?.visible)
                    return Qt.rect(0, 0, 0, 0);
                const p = tray.mapToItem(contentItem, 0, 0);
                return Qt.rect(originX + p.x, originY + p.y, tray.width, tray.height);
            }

            function notificationsButtonContains(x: real, y: real): bool {
                const r = notificationsButtonRect();
                return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
            }

            function launcherButtonRect(): rect {
                const button = bottomHubView.launcherButton;
                if (!visible || !hubRoot.shown || !button?.visible)
                    return Qt.rect(0, 0, 0, 0);
                const p = button.mapToItem(contentItem, 0, 0);
                return Qt.rect(originX + p.x, originY + p.y, button.width, button.height);
            }

            function launcherButtonContains(x: real, y: real): bool {
                const r = launcherButtonRect();
                return x >= r.x && x < r.x + r.width && y >= r.y && y < r.y + r.height;
            }

            function activateLauncher(): void {
                hubRoot.toggleLauncherFor(win.modelData);
            }

            // What the bell does, also for a click that reached it through the scrim.
            function activateNotifications(): void {
                hubRoot.toggleSidebarFor(win.modelData);
            }

            // A screen's state goes away before its window when a monitor is
            // unplugged; null keeps Binding.target (QObject*) from receiving
            // undefined, which Qt logs as "Unable to assign".
            Binding {
                target: win.cortetsuState ?? null
                property: "bottomHub"
                value: win
                when: !!win.cortetsuState
            }

            function toggleSession(): void {
                if (!screenState)
                    return;

                if (!screenState.session)
                    hubRoot.closeAllPopouts();
                OverlayPolicy.toggleOn(CortetsuShellState.allStates(), screenState, "session");
            }

            Process {
                id: cursorPosProcess

                stdout: StdioCollector {
                    onStreamFinished: {
                        const client = win.pendingFocusClient;
                        win.pendingFocusClient = null;

                        if (!client)
                            return;

                        const parts = this.text.trim().split(",");
                        let restoreX = NaN;
                        let restoreY = NaN;

                        if (parts.length >= 2) {
                            restoreX = Number(parts[0].trim());
                            restoreY = Number(parts[1].trim());
                        }

                        win.focusWindowNow(client);

                        if (Number.isFinite(restoreX) && Number.isFinite(restoreY)) {
                            restoreCursorTimer.restoreX = Math.round(restoreX);
                            restoreCursorTimer.restoreY = Math.round(restoreY);
                            restoreCursorTimer.restart();
                        }
                    }
                }
            }

            Timer {
                id: restoreCursorTimer
                interval: 12
                repeat: false
                property int restoreX: 0
                property int restoreY: 0

                onTriggered: {
                    CortetsuHypr.moveCursor(restoreX, restoreY);
                }
            }

            screen: modelData
            visible: !remapping && (hubRoot.shown || toasts.visibleToasts.length > 0 || visibility.autoHideEnabled)
            color: "transparent"

            // Only the islands, the reveal strip and the toasts take the
            // pointer. The air between two islands belongs to what is behind,
            // and so does the place of an island that is switched off.
            mask: Region {
                Region { item: hubRoot.shown && bottomHubView.islands[0].visible ? bottomHubView.islands[0] : null }
                Region { item: hubRoot.shown && bottomHubView.islands[1].visible ? bottomHubView.islands[1] : null }
                Region { item: hubRoot.shown && bottomHubView.islands[2].visible ? bottomHubView.islands[2] : null }
                Region { item: hubRoot.shown && bottomHubView.islands[3].visible ? bottomHubView.islands[3] : null }
                Region {
                    readonly property int strip: win.revealStripVisible ? 3 : 0
                    x: win.hubPlace.edge === "right" ? win.width - strip : 0
                    y: win.hubPlace.edge === "bottom" ? win.height - strip : 0
                    width: win.hubVertical ? strip : win.revealStripVisible ? win.width : 0
                    height: win.hubVertical ? (win.revealStripVisible ? win.height : 0) : strip
                }
                Region {
                    x: toasts.x
                    y: toasts.y
                    width: toasts.width
                    height: toasts.height
                }
            }

            focusable: true
            // Keep toast-only surfaces mapped without asking the compositor for
            // keyboard focus. Keyboard navigation remains available when the
            // hub is explicitly shown.
            WlrLayershell.keyboardFocus: hubRoot.shown
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None

            anchors.top: hubPlace.edge === "top"
            anchors.bottom: hubPlace.edge === "bottom"
            anchors.left: hubPlace.edge === "left"
            anchors.right: hubPlace.edge === "right"
            margins.top: hubPlace.edge === "top" ? edgeMargin : 0
            margins.bottom: hubPlace.edge === "bottom" ? edgeMargin : 0
            margins.left: hubPlace.edge === "left" ? edgeMargin : 0
            margins.right: hubPlace.edge === "right" ? edgeMargin : 0

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.namespace: "cortetsu-bottom-hub"
            // Windows stop short of the islands. The window also grows for
            // toasts, so the zone is the Hub's thickness only, not the
            // window's. The old opaque bar hid windows running under it;
            // floating islands would show them, so the edge is reserved
            // while the Hub is shown.
            exclusiveZone: hubRoot.shown ? bottomHubView.thickness + edgeMargin : 0

            // Room for the toasts beside the Hub, on its inner side.
            // A lateral Hub only widens its window while a toast shows.
            readonly property real toastRoom: 6 + toasts.spacing + (toasts.visibleToasts.length === 0 ? 0
                : hubVertical ? toasts.implicitWidth : toasts.implicitHeight)
            readonly property real innerRoom: Math.max(toastRoom, bottomHubView.tooltipRoom)
            implicitWidth: hubVertical
                ? bottomHubView.thickness + innerRoom
                : (modelData?.width ?? 0) - hubMargin * 2
            implicitHeight: hubVertical
                ? (modelData?.height ?? 0) - hubMargin * 2
                : bottomHubView.thickness + innerRoom

            CortetsuBottomHubView {
                id: bottomHubView

                anchor: win.hubAnchor
                x: win.hubPlace.edge === "right" ? win.width - width : 0
                y: win.hubPlace.edge === "bottom" ? win.height - height : 0
                width: win.hubVertical ? thickness : win.width
                height: win.hubVertical ? win.height : thickness
                visible: hubRoot.shown

                launcherActive: win.screenState?.launcher ?? false
                workspaceCount: win.workspaceCount
                workspaceDisplayType: CortetsuConfig.bar.workspaces.displayType
                workspaceShowAppIcons: CortetsuConfig.bar.workspaces.showAppIcons
                workspaceMonochromeIcons: CortetsuConfig.bar.workspaces.monochromeIcons
                trayMonochromeIcons: CortetsuConfig.bar.tray.recolour
                trayMenuKeyHandler: (key, modifiers) => win.forwardHeldKey(key, modifiers)
                appPreviewKeyHandler: (key, modifiers) => win.forwardHeldKey(key, modifiers)
                openPopoutName: {
                    const popouts = CortetsuShellState.componentsFor(win.modelData)?.popouts;
                    return popouts?.hasCurrent ? popouts.currentName : "";
                }
                engagedPopout: {
                    const popouts = CortetsuShellState.componentsFor(win.modelData)?.popouts;
                    return popouts?.hasCurrent && !popouts.closing && popouts.bottomAttached ? popouts.currentName : "";
                }
                statusPanelOpen: (win.screenState?.sidebar ?? false) || (win.screenState?.session ?? false)
                    || (win.cortetsuState?.calendar ?? false)
                workspaceAppIconSources: win.workspaceAppIconSources
                workspaceOffset: win.workspaceOffset
                activeWsId: win.activeWsId
                occupiedWorkspaceIds: win.occupiedWorkspaceIds
                dockItems: win.dockViewItems
                trayItems: win.trayViewItems
                modeVisible: CortetsuConfig.bottomHub.segments.mode
                appsVisible: CortetsuConfig.bottomHub.segments.apps
                trayVisible: CortetsuConfig.bottomHub.segments.tray
                statusVisible: CortetsuConfig.bottomHub.segments.status

                volumeIcon: win.volumeIcon
                volumeMuted: CortetsuAudio.muted
                networkIcon: win.networkIcon
                networkTooltip: win.networkTooltip
                networkActive: win.networkActive
                bluetoothIcon: win.bluetoothIcon
                bluetoothActive: win.bluetoothActive
                batteryIcon: win.batteryIcon
                batteryCritical: win.batteryCritical
                batteryTooltip: win.batteryTooltip
                audioVisible: CortetsuConfig.bottomHub.statusCluster.audio
                networkVisible: CortetsuConfig.bottomHub.statusCluster.network
                bluetoothVisible: CortetsuConfig.bottomHub.statusCluster.bluetooth
                batteryVisible: CortetsuConfig.bottomHub.statusCluster.battery
                statusPopoutsEnabled: CortetsuConfig.bar.popouts.statusIcons
                notificationCount: CortetsuNotifications.count
                sidebarActive: win.screenState?.sidebar ?? false
                recordingActive: CortetsuRecorder.running
                dndActive: CortetsuNotifications.dnd
                idleInhibited: CortetsuIdleInhibitor.enabled
                now: Time.date
                sessionActive: win.screenState?.session ?? false

                onLauncherRequested: hubRoot.toggleLauncherFor(win.modelData)
                onWorkspaceRequested: workspaceId => CortetsuHypr.focusWorkspace(workspaceId)
                onAppActivateRequested: key => win.activateDockKey(key)
                onAppTogglePinnedRequested: key => win.togglePinnedKey(key)
                onAppCloseRequested: key => win.closeDockKey(key)
                onAppCycleRequested: (key, direction) => win.cycleDockKey(key, direction)
                onAppPreviewHoverRequested: (key, centerX) => win.showAppPreview(key, centerX)
                onAppPreviewHoverEnded: hoverSurfaceController.leaveTrigger()
                onAppPreviewRequested: (key, centerX) => win.openAppPreview(key, centerX)
                onTrayHoverRequested: (itemKey, centerX) => win.showTrayMenu(itemKey, centerX)
                // Without it a tray menu opened by hover stayed open after the
                // pointer left the icon for anywhere but the menu itself.
                onTrayHoverEnded: hoverSurfaceController.leaveTrigger()
                onTrayActivateRequested: itemKey => win.activateTrayItem(itemKey)
                onTraySecondaryActivateRequested: itemKey => win.activateTraySecondary(itemKey)
                onTrayScrollRequested: (itemKey, delta, horizontal) =>
                    win.scrollTrayItem(itemKey, delta, horizontal)
                onTraySecondaryRequested: (itemKey, centerX) => win.openTrayMenu(itemKey, centerX)
                onAttachedControlRequested: (mode, centerX) => hubRoot.showAttachedControlFor(
                    win.modelData,
                    mode,
                    win.alongScreen(centerX)
                )
                onAttachedControlEntered: (mode, centerX) => hubRoot.enterAttachedControl(
                    win.modelData,
                    mode,
                    win.alongScreen(centerX)
                )
                onSystemControlsEntered: hoverSurfaceController.enterTrigger()
                onSystemControlsExited: hoverSurfaceController.leaveTrigger()
                onDetachedControlRequested: mode => hubRoot.toggleDetachedControlFor(win.modelData, mode)
                onVolumeMuteRequested: {
                    if (CortetsuAudio.sink?.audio)
                        CortetsuAudio.sink.audio.muted = !CortetsuAudio.sink.audio.muted;
                }
                onVolumeWheel: delta => {
                    if (!CortetsuConfig.bar.scrollActions.volume)
                        return;
                    if (delta > 0)
                        CortetsuAudio.incrementVolume();
                    else if (delta < 0)
                        CortetsuAudio.decrementVolume();
                }
                onNotificationsRequested: hubRoot.toggleSidebarFor(win.modelData)
                onStopRecordingRequested: CortetsuRecorder.stop()
                onToggleDndRequested: CortetsuNotifications.toggleDnd()
                onToggleIdleInhibitorRequested: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
                onCalendarRequested: hubRoot.openCalendarFor(win.modelData)
                onSessionRequested: win.toggleSession()
            }

            CortetsuBottomHubHoverTarget {
                anchors.fill: parent
                enabled: visibility.autoHideEnabled
                onPointerEntered: {
                    hideTimer.stop();
                    visibility.pointerEntered();
                }
                onPointerExited: visibility.pointerExited()
            }

            // Toasts stack on the Hub's inner side, at the screen's right
            // (bottom right for a lateral Hub).
            Toasts.Toasts {
                id: toasts
                x: win.hubPlace.edge === "left" ? bottomHubView.width + spacing
                    : win.hubPlace.edge === "right" ? bottomHubView.x - width - spacing
                    : win.width - width - spacing
                y: win.hubPlace.edge === "top" ? bottomHubView.height + spacing
                    : win.hubPlace.edge === "bottom" ? bottomHubView.y - height - spacing
                    : win.height - height - spacing
                z: 100
            }

            Connections {
                target: CortetsuToaster

                function onFocusRequested(id: int): void {
                    const screen = CortetsuShellState.forActive()?.modelData;
                    if (!screen || screen !== win.modelData)
                        return;
                    hubRoot.setShown(true);
                    Qt.callLater(() => toasts.focusToast(id));
                }
            }
        }
    }
}
