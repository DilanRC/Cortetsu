import QtQuick
import Quickshell
import Quickshell.Io
import "../components/misc"
import "../services"
import "."
import "CortetsuOverlayPolicy.js" as OverlayPolicy

Scope {
    id: root
    property bool launcherInterrupted: false
    readonly property bool hasFullscreen: CortetsuHypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    function toggleExclusive(state, flag: string): bool {
        if (!state || typeof state[flag] !== "boolean")
            return false;
        const opening = !state[flag];
        if (opening)
            OverlayPolicy.closeAll(state);
        state[flag] = opening;
        return opening;
    }

    CustomShortcut {
        name: "showall"; description: "Alternar lanzador, panel y OSD"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive();
            if (!state) return;
            const open = !(state.launcher || state.dashboard || state.osd || state.utilities || state.qsd || state.settings);
            state.launcher = open && CortetsuConfig.launcher.enabled;
            state.dashboard = open && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard;
            state.osd = open;
            state.utilities = open && CortetsuConfig.utilities.enabled;
            state.qsd = open;
            state.settings = open;
        }
    }
    CustomShortcut {
        name: "dashboard"; description: "Alternar panel"
        onPressed: if (!root.hasFullscreen && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard)
            root.toggleExclusive(CortetsuShellState.forActive(), "dashboard")
    }
    CustomShortcut {
        name: "session"; description: "Alternar menú de sesión"
        onPressed: if (!root.hasFullscreen) root.toggleExclusive(CortetsuShellState.forActive(), "session")
    }
    CustomShortcut {
        name: "launcher"; description: "Alternar lanzador"
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen)
                Quickshell.execDetached(["qs", "-p", `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/quickshell/cortetsu/current`, "ipc", "call", "customDock", "launcher"]);
            root.launcherInterrupted = false;
        }
    }
    CustomShortcut { name: "launcherInterrupt"; description: "Interrumpir atajo del lanzador"; onPressed: root.launcherInterrupted = true }
    CustomShortcut {
        name: "sidebar"; description: "Alternar notificaciones"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive();
            if (!state) return;
            const open = !state.sidebar;
            if (open)
                OverlayPolicy.closeAll(state);
            state.sidebar = open;
            // Super+N is the notification center. Quick settings have their
            // own surface and must not be forced open with notifications.
            state.utilities = false;
            state.cortetsuState?.setRetained("wallpaperManager", false);
        }
    }
    CustomShortcut {
        name: "utilities"; description: "Alternar utilidades"
        onPressed: if (!root.hasFullscreen) root.toggleExclusive(CortetsuShellState.forActive(), "utilities")
    }
    CustomShortcut {
        name: "qsd"; description: "Alternar ajustes rápidos"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            root.toggleExclusive(state, "qsd");
            state.qsdOpenedByShortcut = state.qsd;
            state.qsdEdgeHovered = false;
        }
    }
    CustomShortcut {
        name: "settings"; description: "Alternar centro de ajustes de Cortetsu"
        onPressed: if (!root.hasFullscreen) root.toggleExclusive(CortetsuShellState.forActive(), "settings")
    }

    IpcHandler {
        target: "drawers"
        function toggle(drawer: string): void {
            const state = CortetsuShellState.forActive();
            if (!state || typeof state[drawer] !== "boolean") return;
            if (root.hasFullscreen && ["launcher", "session", "dashboard", "utilities", "qsd", "settings"].includes(drawer)) return;
            if (["launcher", "session", "dashboard", "utilities", "qsd", "settings"].includes(drawer))
                root.toggleExclusive(state, drawer);
            else
                state[drawer] = !state[drawer];
            if (drawer === "qsd") {
                state.qsdOpenedByShortcut = state.qsd;
                state.qsdEdgeHovered = false;
            }
        }
        function list(): string { const state = CortetsuShellState.forActive(); return state ? Object.keys(state).filter(k => typeof state[k] === "boolean").join("\n") : ""; }
        function isOpen(drawer: string): string { const state = CortetsuShellState.forActive(); return !state || typeof state[drawer] !== "boolean" ? "unknown" : state[drawer] ? "1" : "0"; }
    }
}
