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

    function toggleSettingsFullscreen(): void {
        const state = CortetsuShellState.forActive();
        if (!state || !state.settings)
            return;
        CortetsuHypr.dispatch(CortetsuHypr.usingLua
            ? "hl.dsp.window.fullscreen({ mode = 'fullscreen' })"
            : "fullscreen");
    }

    CustomShortcut {
        name: "showall"; description: "Alternar lanzador, panel y OSD"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive();
            if (!state) return;
            const open = !(state.launcher || state.dashboard || state.osd || state.utilities || state.settings);
            state.launcher = open && CortetsuConfig.launcher.enabled;
            state.dashboard = open && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard;
            state.osd = open;
            state.utilities = false;
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
        onPressed: if (!root.hasFullscreen) root.toggleExclusive(CortetsuShellState.forActive(), "osd")
    }
    CustomShortcut {
        name: "osd"; description: "Alternar OSD de acciones rápidas"
        onPressed: {
            if (root.hasFullscreen)
                return;
            root.toggleExclusive(CortetsuShellState.forActive(), "osd");
        }
    }
    CustomShortcut {
        name: "qsd"; description: "Alternar ajustes rápidos"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            // Compatibility name: the compact QSD was removed from the
            // shell. Existing Hyprland bindings now open the full OSD.
            root.toggleExclusive(state, "osd");
        }
    }
    CustomShortcut {
        name: "settings"; description: "Alternar centro de ajustes de Cortetsu"
        onPressed: {
            if (root.hasFullscreen)
                return;
            const state = CortetsuShellState.forActive();
            if (!state)
                return;
            root.toggleExclusive(state, "settings");
        }
    }
    IpcHandler {
        target: "settings"

        function toggleFullscreen(): void { root.toggleSettingsFullscreen(); }
    }

    IpcHandler {
        // Hyprland's global binding uses cortetsu:settingsFullscreen.
        target: "cortetsu"

        function settingsFullscreen(): void { root.toggleSettingsFullscreen(); }
    }

    IpcHandler {
        target: "drawers"
        function toggle(drawer: string): void {
            const state = CortetsuShellState.forActive();
            const target = drawer === "qsd" ? "osd" : drawer;
            if (!state || typeof state[target] !== "boolean") return;
            if (root.hasFullscreen && ["launcher", "session", "dashboard", "utilities", "settings"].includes(target)) return;
            if (["launcher", "session", "dashboard", "utilities", "settings"].includes(target))
                root.toggleExclusive(state, target);
            else
                state[target] = !state[target];
        }
        function list(): string { const state = CortetsuShellState.forActive(); return state ? Object.keys(state).filter(k => typeof state[k] === "boolean").join("\n") : ""; }
        function isOpen(drawer: string): string { const state = CortetsuShellState.forActive(); return !state || typeof state[drawer] !== "boolean" ? "unknown" : state[drawer] ? "1" : "0"; }
    }
}
