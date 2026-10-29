import Quickshell
import Quickshell.Io
import "."
import "SurfaceRegistry.js" as SurfaceRegistry
import "CortetsuShellInspect.js" as ShellInspect

// A soft reload reparses the promoted generation while keeping the Quickshell
// process and reusable windows alive. This is the safe adoption path for
// visual changes while desktop tray applications remain open.
Scope {
    id: root

    function inspectionInput(): var {
        const screens = Quickshell.screens.map(screen => {
            const state = CortetsuShellState.forScreen(screen);
            const typed = state?.cortetsuState;
            const panels = CortetsuShellState.componentsFor(screen);
            const popup = panels?.popouts;
            const monitor = CortetsuHypr.monitorFor(screen);
            const fullscreenProgress = Number(typed?.fullscreenTransitionProgress ?? 0);
            const transitions = [];
            if (fullscreenProgress > 0 && fullscreenProgress < 1)
                transitions.push({ surface: "drawers.fullscreen", active: true, progress: fullscreenProgress });
            if (popup?.closing)
                transitions.push({ surface: "bottom-hub.popup", active: true, progress: null });

            return {
                screen,
                name: screen.name,
                monitor,
                surfaces: SurfaceRegistry.surfaces.map(surface => ({
                    name: surface.name,
                    kind: surface.kind,
                    exclusive: surface.exclusive,
                    ownsKeyboard: surface.ownsKeyboard,
                    open: state?.[surface.name] === true,
                    openCause: state?.[surface.name] === true
                        ? typed?.openCause(surface.name) ?? "explicit" : null
                })),
                focusGrab: {
                    requested: typed?.focusGrabRequested === true,
                    active: typed?.focusGrabActive === true,
                    observable: true,
                    clearedAt: Number(state?.sidebarGrabClearedAt ?? 0),
                    surface: "drawers",
                    windows: typed?.bottomHub ? ["drawers", "bottom_hub"] : ["drawers"]
                },
                bottomHub: {
                    shown: typed?.bottomHub?.hubShown === true,
                    sidebar: state?.sidebar === true,
                    utilities: state?.utilities === true,
                    launcher: state?.launcher === true,
                    popup: popup?.currentName ?? "",
                    open: popup?.hasCurrent === true,
                    closing: popup?.closing === true,
                    detached: popup?.detachedMode ?? "",
                    activeFocus: typed?.bottomHub?.active === true,
                    keyboardFocusPolicy: typed?.bottomHub?.keyboardFocusPolicyName ?? "none"
                },
                keyboardHosts: [
                    { surface: "drawers", window: typed?.drawerWindow,
                        policy: typed?.drawerWindow?.keyboardFocusPolicyName ?? "none" },
                    { surface: "launcher", window: typed?.launcherWindow,
                        policy: typed?.launcherWindow?.keyboardFocusPolicyName ?? "none" },
                    { surface: "dashboard", window: typed?.dashboardWindow,
                        policy: typed?.dashboardWindow?.keyboardFocusPolicyName ?? "none" },
                    { surface: "session", window: typed?.sessionWindow,
                        policy: typed?.sessionWindow?.keyboardFocusPolicyName ?? "none" },
                    { surface: "retained_surfaces", window: typed?.retainedSurfacesWindow,
                        policy: typed?.retainedSurfacesWindow?.keyboardFocusPolicyName ?? "none" },
                    { surface: "bottom_hub", window: typed?.bottomHub,
                        policy: typed?.bottomHub?.keyboardFocusPolicyName ?? "none" }
                ],
                transitions,
                focusGrabActive: typed?.focusGrabActive === true
            };
        });
        const monitors = screens.map(entry => {
            const activeWorkspace = entry.monitor?.activeWorkspace;
            const ipcMonitor = entry.monitor?.lastIpcObject ?? {};
            return {
                name: entry.name,
                x: Number(entry.screen.x ?? 0),
                y: Number(entry.screen.y ?? 0),
                width: Number(entry.screen.width ?? 0),
                height: Number(entry.screen.height ?? 0),
                scale: Number(entry.screen.devicePixelRatio ?? entry.screen.scale ?? 1),
                focused: entry.monitor === CortetsuHypr.focusedMonitor,
                active_workspace: activeWorkspace
                    ? { id: activeWorkspace.id, name: activeWorkspace.name }
                    : null,
                dpms_on: typeof ipcMonitor.dpmsStatus === "boolean" ? ipcMonitor.dpmsStatus : null
            };
        });
        const workspaceToplevels = CortetsuHypr.focusedWorkspace?.toplevels?.values ?? [];
        const activeWindow = CortetsuHypr.focusedToplevel
            ?? workspaceToplevels.find(toplevel => Number(toplevel.lastIpcObject?.focusHistoryID) === 0)
            ?? null;
        const window = activeWindow?.lastIpcObject ?? null;
        const windowMonitor = window && Number.isFinite(Number(window.monitor))
            ? screens.find(entry => Number(entry.monitor?.id) === Number(window.monitor))?.name ?? null
            : null;
        const fullscreenWindows = (CortetsuHypr.focusedWorkspace?.toplevels?.values ?? [])
            .filter(toplevel => Number(toplevel.lastIpcObject?.fullscreen ?? 0) > 1)
            .map(toplevel => ({
                address: String(toplevel.lastIpcObject?.address ?? ""),
                class: String(toplevel.lastIpcObject?.class ?? "")
            }));
        const activeFocusGrabs = screens.filter(entry => entry.focusGrabActive);
        const keyboardCandidates = [];
        for (const entry of screens) {
            for (const host of entry.keyboardHosts) {
                if (host.policy !== "none")
                    keyboardCandidates.push({
                        monitor: entry.name,
                        surface: host.surface,
                        policy: host.policy,
                        active: host.window?.active === true
                    });
            }
        }
        const keyboardOwner = ShellInspect.resolveKeyboardOwner({
            focusGrabs: activeFocusGrabs.map(entry => ({ monitor: entry.name, active: true })),
            hosts: keyboardCandidates,
            focusedToplevel: window ? { monitor: windowMonitor } : null
        });

        return {
            observedAt: new Date().toISOString(),
            monitors,
            screens,
            focus: {
                monitor: CortetsuHypr.focusedMonitor?.name ?? null,
                workspace: CortetsuHypr.focusedWorkspace
                    ? { id: CortetsuHypr.focusedWorkspace.id, name: CortetsuHypr.focusedWorkspace.name }
                    : null,
                window: window ? {
                    address: String(window.address ?? ""),
                    class: String(window.class ?? ""),
                    monitor: windowMonitor
                } : null,
                keyboardOwner
            },
            fullscreen: { focused: CortetsuHypr.focusedFullscreen, windows: fullscreenWindows },
            hyprlandQueries: { clientSnapshots: {
                count: CortetsuHypr.clientsQueryCount,
                totalMs: CortetsuHypr.clientsQueryTotalMs,
                maxMs: CortetsuHypr.clientsQueryMaxMs
            }, toplevelRefreshCalls: CortetsuHypr.eventToplevelRefreshCalls,
            windowTitleRefreshCalls: CortetsuHypr.windowTitleRefreshCalls },
            eventStream: {
                quickshellReconnectSupported: false,
                quickshellStatusObservable: false,
                lost: CortetsuHypr.eventStreamLost,
                cortetsuObserverReconnectSupported: true
            }
        };
    }

    IpcHandler {
        target: "cortetsu-shell"

        function reload(): void {
            Quickshell.reload(false);
        }

        function inspect(): string {
            return ShellInspect.stringifySnapshot(root.inspectionInput());
        }
    }
}
