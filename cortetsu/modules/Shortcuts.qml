import QtQuick
import Quickshell
import Quickshell.Io
import "../components/misc"
import "../services"
import "."
import "CortetsuOverlayPolicy.js" as OverlayPolicy
import "SurfaceRegistry.js" as Surfaces

Scope {
    id: root
    property bool launcherInterrupted: false
    readonly property bool hasFullscreen: CortetsuHypr.focusedFullscreen

    // The one toggle for every shortcut and `drawers toggle`: the same
    // operation follows the same policy whichever path asks for it.
    function toggleSurface(state, flag: string): bool {
        return OverlayPolicy.toggleGuarded(CortetsuShellState.allStates(), state, flag, root.hasFullscreen);
    }

    CustomShortcut {
        name: "showall"; description: "Alternar lanzador, panel y OSD"
        onPressed: {
            if (root.hasFullscreen) return;
            const state = CortetsuShellState.forActive();
            if (!state) return;
            const open = !(state.launcher || state.dashboard || state.osd || state.utilities);
            // Shows three panels together on purpose; they still close
            // whatever exclusive surface is open on any screen.
            if (open)
                OverlayPolicy.closeExclusiveEverywhere(CortetsuShellState.allStates());
            state.launcher = open && CortetsuConfig.launcher.enabled;
            state.dashboard = open && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard;
            state.osd = open;
            state.utilities = false;
        }
    }
    CustomShortcut {
        name: "dashboard"; description: "Alternar panel"
        onPressed: if (CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard)
            root.toggleSurface(CortetsuShellState.forActive(), "dashboard")
    }
    CustomShortcut {
        name: "session"; description: "Alternar menú de sesión"
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "session")
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
        // Super+N is the notification center. Opening it closes every
        // exclusive surface (quick settings and Wallpaper Manager included).
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "sidebar")
    }
    CustomShortcut {
        name: "focusToast"; description: "Enfocar la notificación más reciente"
        onPressed: CortetsuToaster.requestFocusNewest()
    }
    CustomShortcut {
        name: "utilities"; description: "Alternar utilidades"
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "osd")
    }
    CustomShortcut {
        name: "osd"; description: "Alternar OSD de acciones rápidas"
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "osd")
    }
    CustomShortcut {
        name: "qsd"; description: "Alternar ajustes rápidos"
        // Compatibility name: the compact QSD was removed from the shell.
        // Existing Hyprland bindings now open the full OSD.
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "osd")
    }
    CustomShortcut {
        name: "settings"; description: "Alternar centro de ajustes de Cortetsu"
        onPressed: root.toggleSurface(CortetsuShellState.forActive(), "settings")
    }
    IpcHandler {
        target: "drawers"
        function toggle(drawer: string): void {
            const state = CortetsuShellState.forActive();
            const target = drawer === "qsd" ? "osd" : drawer;
            if (!state || !Surfaces.isKnown(target)) return;
            if (target === "launcher" && CortetsuShellState.launcherOpenAnywhere())
                CortetsuShellState.closeLaunchers(null);
            else if (Surfaces.isSettable(target))
                root.toggleSurface(state, target);
            else
                state[target] = !state[target]; // bar: chrome, outside the overlay policy
        }
        function list(): string { const state = CortetsuShellState.forActive(); return state ? Object.keys(state).filter(k => Surfaces.isKnown(k)).join("\n") : ""; }
        // Screens whose launcher is open; the single-state contract keeps it to one line at most.
        function launcherScreens(): string { return CortetsuShellState.states.filter(entry => !!entry.state?.launcher).map(entry => entry.screen?.name ?? "").join("\n"); }
        function isOpen(drawer: string): string { const state = CortetsuShellState.forActive(); return !state || !Surfaces.isKnown(drawer) ? "unknown" : state[drawer] ? "1" : "0"; }
    }

    // Toasts for Hyprland binds and scripts: `cortetsu shell ipc toaster info
    // <title> <message> <icon>`. `error` shows the urgent style.
    IpcHandler {
        target: "toaster"
        function info(title: string, message: string, icon: string): void { CortetsuToaster.toast(title, message, icon || "info"); }
        function error(title: string, message: string): void { CortetsuToaster.toast(title, message, "error", 2); }
    }
}
