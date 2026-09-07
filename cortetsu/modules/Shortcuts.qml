import QtQuick
import Quickshell
import Quickshell.Io
import "../components/misc"
import "../services"
import qs.modules

Scope {
    id: root
    property bool launcherInterrupted: false
    readonly property bool hasFullscreen: CortetsuHypr.focusedWorkspace?.toplevels.values.some(t => t.lastIpcObject.fullscreen > 1) ?? false

    CustomShortcut {
        name: "showall"; description: "Toggle launcher, dashboard and osd"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive();
            state.launcher = state.dashboard = state.osd = state.utilities = state.qsd = state.settings = !(state.launcher || state.dashboard || state.osd || state.utilities || state.qsd || state.settings);
        }
    }
    CustomShortcut { name: "dashboard"; description: "Toggle dashboard"; onPressed: if (!root.hasFullscreen) CortetsuShellState.forActive().dashboard = !CortetsuShellState.forActive().dashboard }
    CustomShortcut { name: "session"; description: "Toggle session menu"; onPressed: if (!root.hasFullscreen) CortetsuShellState.forActive().session = !CortetsuShellState.forActive().session }
    CustomShortcut {
        name: "launcher"; description: "Toggle launcher"
        onPressed: root.launcherInterrupted = false
        onReleased: {
            if (!root.launcherInterrupted && !root.hasFullscreen)
                Quickshell.execDetached(["qs", "-p", `${Quickshell.env("XDG_CONFIG_HOME") || `${Quickshell.env("HOME")}/.config`}/quickshell/cortetsu/current`, "ipc", "call", "customDock", "launcher"]);
            root.launcherInterrupted = false;
        }
    }
    CustomShortcut { name: "launcherInterrupt"; description: "Interrupt launcher keybind"; onPressed: root.launcherInterrupted = true }
    CustomShortcut {
        name: "sidebar"; description: "Toggle sidebar"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive(), open = !(state.sidebar || state.utilities);
            state.sidebar = open; state.utilities = open; state.cortetsuState?.setRetained("wallpaperManager", false);
        }
    }
    CustomShortcut { name: "utilities"; description: "Toggle utilities"; onPressed: if (!root.hasFullscreen) CortetsuShellState.forActive().utilities = !CortetsuShellState.forActive().utilities }
    CustomShortcut {
        name: "qsd"; description: "Toggle Quick Settings Drawer"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const state = CortetsuShellState.forActive();
            state.qsd = !state.qsd;
            state.qsdOpenedByShortcut = state.qsd;
            state.qsdEdgeHovered = false;
        }
    }
    CustomShortcut { name: "settings"; description: "Toggle Cortetsu Settings Center"; onPressed: if (!root.hasFullscreen) CortetsuShellState.forActive().settings = !CortetsuShellState.forActive().settings }

    IpcHandler {
        target: "drawers"
        function toggle(drawer: string): void {
            const state = CortetsuShellState.forActive();
            if (!state || typeof state[drawer] !== "boolean") return;
            if (root.hasFullscreen && ["launcher", "session", "dashboard", "qsd"].includes(drawer)) return;
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
