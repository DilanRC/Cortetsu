pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../modules"

// Visual game mode. cortetsu-gamemode snapshots the options it changes and
// restores only those still holding the game value, without `hyprctl reload`,
// so changes made from Settings while it is on survive. Feral GameMode, power
// profiles and GPU selection are separate and untouched here.
Singleton {
    id: root

    property alias enabled: state.enabled
    property bool recovering: false

    function notify(title: string, message: string): void {
        if (CortetsuConfig.toastGameModeChanged)
            Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", title, message]);
    }

    function run(action: string): void {
        Quickshell.execDetached(CortetsuHypr.usingLua
            ? ["cortetsu-gamemode", action]
            : ["cortetsu-gamemode", action, "--keyword"]);
    }

    function toggle(): void { enabled = !enabled; }

    onEnabledChanged: {
        if (recovering)
            return;
        run(enabled ? "enable" : "disable");
        if (enabled)
            notify(qsTr("Modo juego activado"), qsTr("Animaciones y efectos reducidos"));
        else
            notify(qsTr("Modo juego desactivado"), qsTr("Configuración de Hyprland restaurada"));
    }

    PersistentProperties {
        id: state
        property bool enabled: false
        reloadableId: "gameMode"
    }

    // A shell restarted while game mode was on finds the snapshot of the
    // running Hyprland and shows it as on, so turning it off restores.
    Process {
        running: true
        command: ["cortetsu-gamemode", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let active = false;
                try {
                    active = JSON.parse(text).enabled === true;
                } catch (error) {
                    return;
                }
                if (active === root.enabled)
                    return;
                root.recovering = true;
                root.enabled = active;
                root.recovering = false;
            }
        }
    }

    IpcHandler {
        target: "gameMode"
        function isEnabled(): bool { return root.enabled; }
        function toggle(): void { root.toggle(); }
        function enable(): void { root.enabled = true; }
        function disable(): void { root.enabled = false; }
    }
}
