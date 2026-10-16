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

    // The user's request. The helper's reply (the snapshot exists or not)
    // decides what stays shown, so a failed apply never reads as on.
    property alias enabled: state.enabled
    property bool recovering: false
    property bool pending: false

    function notify(title: string, message: string): void {
        if (CortetsuConfig.toastGameModeChanged)
            Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", title, message]);
    }

    function toggle(): void { enabled = !enabled; }

    // One helper process at a time; a toggle during a run is applied after.
    function sync(): void {
        if (helper.running) {
            pending = true;
            return;
        }
        const action = enabled ? "enable" : "disable";
        helper.requested = action;
        helper.command = CortetsuHypr.usingLua ? ["cortetsu-gamemode", action] : ["cortetsu-gamemode", action, "--keyword"];
        helper.running = true;
    }

    function settle(active: bool): void {
        if (active === enabled)
            return;
        recovering = true;
        enabled = active;
        recovering = false;
    }

    onEnabledChanged: {
        if (!recovering)
            sync();
    }

    // PersistentProperties keeps the request across a QML reload; the
    // snapshot read by `status` at startup wins after a shell restart.
    PersistentProperties {
        id: state
        property bool enabled: false
        reloadableId: "gameMode"
    }

    Process {
        id: helper
        property string requested: "status"
        running: true
        command: ["cortetsu-gamemode", "status"]
        onRunningChanged: {
            if (!running && root.pending) {
                root.pending = false;
                root.sync();
            }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let active = false;
                try {
                    active = JSON.parse(text).enabled === true;
                } catch (error) {
                    active = false;
                }
                const requested = helper.requested;
                if (root.pending)
                    return; // superseded; onRunningChanged runs the newer request
                root.settle(active);
                if (requested === "enable" && active)
                    root.notify(qsTr("Modo juego activado"), qsTr("Animaciones y efectos reducidos"));
                else if (requested === "disable" && !active)
                    root.notify(qsTr("Modo juego desactivado"), qsTr("Configuración de Hyprland restaurada"));
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
