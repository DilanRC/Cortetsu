pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../modules"

Singleton {
    id: root

    property alias enabled: state.enabled

    function notify(title: string, message: string): void {
        if (CortetsuConfig.toastGameModeChanged)
            Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", title, message]);
    }

    function dispatchKeyword(key: string, value: string): void {
        if (CortetsuHypr.usingLua) {
            const field = key.replaceAll(":", " = ");
            Quickshell.execDetached(["hyprctl", "eval", `hl.config({ ${field} = ${value === "0" ? "false" : "true"} })`]);
        } else {
            Quickshell.execDetached(["hyprctl", "keyword", key, value]);
        }
    }

    function apply(): void {
        if (CortetsuHypr.usingLua) {
            Quickshell.execDetached([
                "hyprctl", "eval",
                "hl.config({ animations = { enabled = false }, decoration = { shadow = { enabled = false }, blur = { enabled = false }, rounding = 0 }, general = { gaps_in = 0, gaps_out = 0, border_size = 1, allow_tearing = true } })"
            ]);
            return;
        }
        for (const setting of [
            ["animations:enabled", "0"], ["decoration:shadow:enabled", "0"],
            ["decoration:blur:enabled", "0"], ["general:gaps_in", "0"],
            ["general:gaps_out", "0"], ["general:border_size", "1"],
            ["decoration:rounding", "0"], ["general:allow_tearing", "1"]
        ])
            dispatchKeyword(setting[0], setting[1]);
    }

    function toggle(): void { enabled = !enabled; }

    onEnabledChanged: {
        if (enabled) {
            apply();
            notify(qsTr("Modo juego activado"), qsTr("Animaciones y efectos reducidos"));
        } else {
            Quickshell.execDetached(["hyprctl", "reload"]);
            notify(qsTr("Modo juego desactivado"), qsTr("Configuración de Hyprland restaurada"));
        }
    }

    PersistentProperties {
        id: state
        property bool enabled: false
        reloadableId: "gameMode"
    }

    IpcHandler {
        target: "gameMode"
        function isEnabled(): bool { return root.enabled; }
        function toggle(): void { root.toggle(); }
        function enable(): void { root.enabled = true; }
        function disable(): void { root.enabled = false; }
    }
}
