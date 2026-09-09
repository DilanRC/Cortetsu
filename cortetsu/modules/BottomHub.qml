pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.SystemTray
import "../services"
import "../utils"
import "launcher/services"
import "OverlayPolicy.js" as OverlayPolicy
import "utilities/toasts" as Toasts

Scope {
    id: hubRoot

    property bool shown: true

    CortetsuHoverSurfaceController {
        id: hoverSurfaceController

        onOpenRequested: (screen, mode, anchorCenter) =>
            hubRoot.openAttachedControlNow(screen, mode, anchorCenter)
        onCloseRequested: hubRoot.closeAllPopouts()
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
        onTriggered: hubRoot.shown = false
    }

    function closeAllLaunchers(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen);
            if (state)
                state.launcher = false;
        }
    }

    function closeAllPanels(): void {
        for (const screen of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(screen);
            OverlayPolicy.closeOtherPanels(state);
        }
    }

    function closeAllPopouts(): void {
        for (const screen of CortetsuScreens.screens) {
            const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
            if (popouts)
                popouts.close();
        }
    }

    function setShown(value): void {
        if (value) {
            hideTimer.stop();
            shown = true;
            return;
        }

        // Let attached popouts finish their return-to-icon animation while
        // the parent panel still owns the full screen geometry.
        hideTimer.restart();
        closeAllLaunchers();
        closeAllPanels();
        closeAllPopouts();
    }

    function toggle(): void {
        setShown(!shown);
    }

    Process {
        id: calendarSync
        command: [Paths.home + "/.local/bin/cortetsu-calendar", "sync"]
    }

    Process {
        id: pomodoroOwner
        command: [Paths.home + "/.local/bin/cortetsu-pomodoro", "daemon"]
        running: true
    }

    Timer {
        id: pomodoroNotificationReload
        interval: 120
        repeat: false
        onTriggered: pomodoroNotification.reload()
    }

    FileView {
        id: pomodoroNotification
        path: `${Quickshell.env("XDG_STATE_HOME") || `${Paths.home}/.local/state`}/cortetsu/pomodoro-notification.json`
        watchChanges: true
        printErrors: false
        property var consumed: 0
        onFileChanged: pomodoroNotificationReload.restart()
        function consumeEvent(raw): void {
            try {
                const event = JSON.parse(raw);
                if (event.sequence !== consumed) {
                    consumed = event.sequence;
                    if (event.title && event.message)
                        CortetsuToaster.toast(event.title, event.message, "timer");
                }
            } catch (_) {}
        }
        onLoaded: consumeEvent(text())
        onTextChanged: consumeEvent(text())
    }

    function openCalendarFor(screen): void {
        closeAllLaunchers();
        closeAllPanels();
        closeAllPopouts();
        const state = CortetsuShellState.forScreen(screen)?.cortetsuState;
        if (state)
            state.setRetained("calendar", !(state.calendar ?? false));
        if (state?.calendar && !calendarSync.running)
            calendarSync.running = true;
        shown = true;
    }

    function toggleLauncherFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;

        const wasOpen = state.launcher;
        closeAllLaunchers();
        closeAllPanels();
        if (!wasOpen)
            closeAllPopouts();
        OverlayPolicy.closeOtherPanels(state);
        state.launcher = !wasOpen;
        shown = true;
    }

    function toggleSidebarFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;

        const wasOpen = state.sidebar || state.utilities;
        closeAllLaunchers();
        closeAllPanels();
        if (!wasOpen)
            closeAllPopouts();
        OverlayPolicy.closeOtherPanels(state);
        state.sidebar = !wasOpen;
        state.utilities = !wasOpen;
        shown = true;
    }

    function toggleUtilitiesFor(screen): void {
        const state = CortetsuShellState.forScreen(screen);
        if (!state)
            return;

        const wasOpen = state.utilities;
        closeAllLaunchers();
        closeAllPanels();
        if (!wasOpen)
            closeAllPopouts();
        OverlayPolicy.closeOtherPanels(state);
        state.utilities = !wasOpen;
        shown = true;
    }

    function openWallpaperFor(screen): void {
        closeAllPopouts();
        for (const candidate of CortetsuScreens.screens) {
            const state = CortetsuShellState.forScreen(candidate)?.cortetsuState;
            if (!state)
                continue;
            OverlayPolicy.closeOtherPanels(state.legacyState);
            state.setRetained("wallpaperManager", candidate === screen);
        }
        shown = true;
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
        shown = true;
    }

    function openAttachedControlNow(screen, mode, anchorCenter = -1): void {
        const popouts = CortetsuShellState.componentsFor(screen)?.popouts;
        if (!popouts)
            return;

        closeAllLaunchers();
        closeAllPanels();
        popouts.cancelClose();
        popouts.detachedMode = "";
        popouts.bottomAnchorCenter = anchorCenter;
        popouts.bottomAttached = true;
        popouts.currentName = mode;
        popouts.hasCurrent = true;
        shown = true;
    }

    function showAttachedControlFor(screen, mode, anchorCenter = -1): void {
        hoverSurfaceController.request(screen, mode, anchorCenter);
    }

    function enterAttachedControl(screen, mode, anchorCenter = -1): void {
        hoverSurfaceController.enterTrigger();
        hoverSurfaceController.request(screen, mode, anchorCenter);
    }

    IpcHandler {
        target: "bottomHub"

        function toggle(): void { hubRoot.toggle(); }
        function show(): void { hubRoot.setShown(true); }
        function hide(): void { hubRoot.setShown(false); }
        function isShown(): bool { return hubRoot.shown; }
        // Read-only runtime evidence for focus, lifetime and monitor ownership.
        function inspect(): string {
            return JSON.stringify(CortetsuScreens.screens.map(screen => {
                const state = CortetsuShellState.forScreen(screen);
                const popup = CortetsuShellState.componentsFor(screen)?.popouts;
                return { screen: screen.name, launcher: state?.launcher ?? false,
                    utilities: state?.utilities ?? false, sidebar: state?.sidebar ?? false,
                    popup: popup?.currentName ?? "", open: popup?.hasCurrent ?? false,
                    closing: popup?.closing ?? false, detached: popup?.detachedMode ?? "",
                    anchor: popup?.bottomAnchorCenter ?? -1, focus: popup?.activeFocus ?? false };
            }));
        }
        function launcher(): void {
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            hubRoot.toggleLauncherFor(state.modelData);
        }
        function notifications(): void {
            hubRoot.toggleSidebarFor(CortetsuShellState.forActive()?.modelData);
        }
        function quickSettings(): void {
            hubRoot.toggleUtilitiesFor(CortetsuShellState.forActive()?.modelData);
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
            hubRoot.showAttachedControlFor(screen, mode);
            return true;
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
    }

    Variants {
        model: CortetsuScreens.screens

        PanelWindow {
            id: win

            required property ShellScreen modelData

            readonly property var monitor: CortetsuScreens.monitorFor(modelData)
            readonly property var screenState: CortetsuShellState.forScreen(modelData)
            readonly property var cortetsuState: screenState?.cortetsuState
            readonly property string activeAddress:
                CortetsuHypr.activeToplevel?.lastIpcObject?.address ?? ""
            readonly property bool panelActive:
                (screenState?.launcher ?? false)
                || (cortetsuState?.overview ?? false)
                || (screenState?.sidebar ?? false)
                || (screenState?.session ?? false)
                || (cortetsuState?.calendar ?? false)
            readonly property int hubMargin: 8
            readonly property int activeWsId: CortetsuConfig.bar.workspaces.perMonitorWorkspaces
                ? monitor?.activeWorkspace?.id ?? CortetsuHypr.activeWsId
                : CortetsuHypr.activeWsId
            readonly property int workspaceCount: CortetsuConfig.workspacesShown
            readonly property int workspaceOffset: Math.floor((activeWsId - 1) / workspaceCount) * workspaceCount
            readonly property var occupiedWorkspaceIds: CortetsuHypr.workspaces.values
                .filter(ws => ws.lastIpcObject?.windows > 0)
                .map(ws => ws.id)

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
                ? qsTr("Connecting to network")
                : CortetsuNetwork.activeEthernet
                    ? qsTr("Ethernet connected")
                    : CortetsuNetwork.active
                        ? qsTr("%1 · signal %2%").arg(CortetsuNetwork.active.ssid).arg(Math.round(CortetsuNetwork.active.strength ?? 0))
                        : qsTr("Network unavailable")
            readonly property bool bluetoothActive: Bluetooth.devices.values.some(device => device.connected)
            readonly property string bluetoothIcon: !Bluetooth.defaultAdapter?.enabled
                ? "bluetooth_disabled"
                : bluetoothActive
                    ? "bluetooth_connected"
                    : "bluetooth"
            readonly property bool batteryCharging: [
                UPowerDeviceState.Charging,
                UPowerDeviceState.FullyCharged,
                UPowerDeviceState.PendingCharge
            ].includes(UPower.displayDevice.state)
            readonly property string batteryIcon: UPower.displayDevice.isLaptopBattery
                ? Icons.getBatteryIcon(UPower.displayDevice.percentage, batteryCharging)
                : "balance"
            readonly property bool batteryCritical:
                UPower.onBattery && UPower.displayDevice.percentage <= 0.2
            readonly property string batteryTooltip: UPower.displayDevice.isLaptopBattery
                ? qsTr("Battery %1%").arg(Math.round(UPower.displayDevice.percentage * 100))
                : qsTr("Power profile")

            property date now: new Date()
            property var pendingFocusClient: null

            readonly property var dockItems: {
                const clients = CortetsuHypr.toplevels.values.filter(client => {
                    if (!CortetsuHypr.isTaskbarToplevel(client))
                        return false;

                    const clientMonitor = client.lastIpcObject?.monitor;
                    return win.monitor && clientMonitor === win.monitor.id;
                });

                const groups = new Map();

                for (const client of clients) {
                    const cls = client.lastIpcObject?.class ?? "";
                    const entry = DesktopEntries.heuristicLookup(cls);
                    const key = entry?.id ?? cls.toLowerCase();

                    if (!groups.has(key)) {
                        groups.set(key, {
                            key: key,
                            entry: entry,
                            className: cls,
                            pinned: false,
                            windows: []
                        });
                    }

                    groups.get(key).windows.push(client);
                }

                const result = [];
                const pinnedEntries = DesktopEntries.applications.values.filter(entry =>
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
                iconSource: item.entry?.icon
                    ? Quickshell.iconPath(item.entry.icon, "image-missing")
                    : Icons.getAppIcon(item.className, "image-missing"),
                windowCount: item.windows.length
            }))

            readonly property var trayViewItems: SystemTray.items.values
                .filter(item => !CortetsuConfig.hiddenTrayIcons.includes(item.id))
                .map(item => ({
                    id: item.id,
                    title: item.id,
                    iconSource: item.icon || Icons.getTrayIcon(item.id, item.icon)
                }))

            function dockItemForKey(key): var {
                return dockItems.find(item => item.key === key) ?? null;
            }

            function trayItemForId(itemId): var {
                return SystemTray.items.values.find(item => item.id === itemId) ?? null;
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

                const selector = `address:${address}`;
                CortetsuHypr.dispatch(
                    CortetsuHypr.usingLua
                        ? `hl.dsp.focus({ window = \"${selector}\" })`
                        : `focuswindow ${selector}`
                );
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

                const selector = `address:${address}`;
                CortetsuHypr.dispatch(
                    CortetsuHypr.usingLua
                        ? `hl.dsp.window.close({ window = \"${selector}\" })`
                        : `closewindow ${selector}`
                );
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

            function showTrayMenu(itemId, centerX): void {
                const item = trayItemForId(itemId);
                if (!item)
                    return;
                const sourceIndex = SystemTray.items.values.indexOf(item);
                if (sourceIndex < 0)
                    return;
                hubRoot.showAttachedControlFor(
                    modelData,
                    `traymenu${sourceIndex}`,
                    hubMargin + centerX
                );
            }

            function activateTrayItem(itemId, secondary = false): void {
                const item = trayItemForId(itemId);
                if (!item)
                    return;
                if (secondary)
                    item.secondaryActivate();
                else
                    item.activate();
            }

            function toggleSession(): void {
                if (!screenState)
                    return;

                const wasOpen = screenState.session;
                hubRoot.closeAllLaunchers();
                hubRoot.closeAllPanels();
                OverlayPolicy.closeOtherPanels(screenState);
                screenState.session = !wasOpen;
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
                    if (CortetsuHypr.usingLua)
                        CortetsuHypr.dispatch(`hl.dsp.cursor.move({ x = ${restoreX}, y = ${restoreY} })`);
                    else
                        CortetsuHypr.dispatch(`movecursor ${restoreX} ${restoreY}`);
                }
            }

            Timer {
                interval: 1000
                repeat: true
                running: true
                onTriggered: win.now = new Date()
            }

            screen: modelData
            visible: hubRoot.shown
            color: "transparent"

            mask: Region {
                Region {
                    x: 0
                    y: win.height - bottomHubView.height
                    width: win.width
                    height: bottomHubView.height
                }
                Region {
                    x: toasts.x
                    y: toasts.y
                    width: toasts.width
                    height: toasts.height
                }
            }

            focusable: true
            WlrLayershell.keyboardFocus: toasts.visibleToasts.length > 0
                ? WlrKeyboardFocus.Exclusive
                : WlrKeyboardFocus.OnDemand

            anchors.bottom: true
            margins.bottom: 2

            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.exclusionMode: ExclusionMode.Ignore

            implicitWidth: (modelData?.width ?? 0) - hubMargin * 2
            implicitHeight: bottomHubView.implicitHeight + 6 + toasts.implicitHeight + toasts.spacing

            CortetsuBottomHubView {
                id: bottomHubView

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: implicitHeight

                launcherActive: win.screenState?.launcher ?? false
                wallpaperActive: win.cortetsuState?.wallpaperManager ?? false
                wallpaperSource: CortetsuWallpapers.actualCurrent
                workspaceCount: win.workspaceCount
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
                now: win.now
                sessionActive: win.screenState?.session ?? false

                onLauncherRequested: hubRoot.toggleLauncherFor(win.modelData)
                onWallpaperRequested: hubRoot.openWallpaperFor(win.modelData)
                onWorkspaceRequested: workspaceId => CortetsuHypr.dispatch(
                    CortetsuHypr.usingLua
                        ? `hl.dsp.focus({ workspace = \"${workspaceId}\" })`
                        : `workspace ${workspaceId}`
                )
                onAppActivateRequested: key => win.activateDockKey(key)
                onAppTogglePinnedRequested: key => win.togglePinnedKey(key)
                onAppCloseRequested: key => win.closeDockKey(key)
                onAppCycleRequested: (key, direction) => win.cycleDockKey(key, direction)
                onTrayHoverRequested: (itemId, centerX) => win.showTrayMenu(itemId, centerX)
                onTrayActivateRequested: itemId => win.activateTrayItem(itemId)
                onTraySecondaryRequested: itemId => win.activateTrayItem(itemId, true)
                onAttachedControlRequested: (mode, centerX) => hubRoot.showAttachedControlFor(
                    win.modelData,
                    mode,
                    win.hubMargin + centerX
                )
                onAttachedControlEntered: (mode, centerX) => hubRoot.enterAttachedControl(
                    win.modelData,
                    mode,
                    win.hubMargin + centerX
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
                onToggleDndRequested: CortetsuNotifications.dnd = !CortetsuNotifications.dnd
                onToggleIdleInhibitorRequested: CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled
                onCalendarRequested: hubRoot.openCalendarFor(win.modelData)
                onSessionRequested: win.toggleSession()
            }

            Toasts.Toasts {
                id: toasts
                anchors.right: parent.right
                anchors.bottom: bottomHubView.top
                anchors.margins: toasts.spacing
                z: 100
            }
        }
    }
}
