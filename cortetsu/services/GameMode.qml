pragma Singleton

import QtQml
import Quickshell
import Quickshell.Io
import "../modules"

// Visual game mode, applied by cortetsu-gamemode (see docs/GAME_MODE.md).
// Three things are kept apart:
//   status   what the helper last confirmed; the only source of `enabled`
//   desired  the user's request while it is not yet confirmed (null: none)
//   busy     a helper is running, so the UI can say so
// A QML reload or shell restart starts from `status` and never re-applies.
Singleton {
    id: root

    // INACTIVE, ACTIVE, APPLYING, RESTORING, RECOVERY_REQUIRED or UNKNOWN.
    property string status: "UNKNOWN"
    property string error: ""
    readonly property bool enabled: status === "ACTIVE"
    readonly property bool busy: helper.running || helper.awaiting
    // A pending state seen while no helper of ours runs was interrupted.
    readonly property bool needsRecovery: !busy && ["APPLYING", "RESTORING", "RECOVERY_REQUIRED"].includes(status)
    property var desired: null
    property int request: 0

    function notify(title: string, message: string): void {
        Quickshell.execDetached(["notify-send", "--app-name=Cortetsu", title, message]);
    }

    // In a failed state the only safe request is "off", which recovers.
    function toggle(): void { setEnabled(needsRecovery ? false : !(desired ?? enabled)); }

    function setEnabled(on: bool): void {
        desired = on;
        request++;
        sync();
    }

    // One helper process at a time; a request made during a run waits for it.
    function sync(): void {
        if (busy || desired === null)
            return;
        if (desired === enabled && (status === "ACTIVE" || status === "INACTIVE")) {
            desired = null;
            return;
        }
        run(desired ? "enable" : "disable");
    }

    function run(action: string): void {
        helper.action = action;
        helper.serving = request;
        helper.awaiting = true;
        helper.command = CortetsuHypr.usingLua ? ["cortetsu-gamemode", action] : ["cortetsu-gamemode", action, "--keyword"];
        helper.running = true;
    }

    function finish(text: string): void {
        let reply = null;
        try {
            reply = JSON.parse(text);
        } catch (parseError) {
            reply = { state: "UNKNOWN", ok: false, error: qsTr("cortetsu-gamemode no respondió") };
        }
        const wasOn = enabled;
        status = reply.state;
        error = reply.error ?? "";
        const action = helper.action;
        helper.awaiting = false;
        if (helper.serving === request && action !== "status")
            desired = null; // answered, success or not; a failure is not retried
        if (!reply.ok)
            notify(qsTr("Modo juego: error"), error);
        else if (CortetsuConfig.toastGameModeChanged && wasOn !== enabled)
            notify(enabled ? qsTr("Modo juego activado") : qsTr("Modo juego desactivado"),
                   enabled ? qsTr("Animaciones y efectos reducidos") : qsTr("Configuración de Hyprland restaurada"));
        Qt.callLater(sync);
    }

    // startup inventory: cortetsu:gamemode-control
    Process {
        id: helper
        property string action: "status"
        property int serving: 0
        property bool awaiting: true
        running: true
        command: ["cortetsu-gamemode", "status"]
        onRunningChanged: if (!running) Qt.callLater(root.sync)
        stdout: StdioCollector {
            onStreamFinished: root.finish(text)
        }
    }

    IpcHandler {
        target: "gameMode"
        function isEnabled(): bool { return root.enabled; }
        function status(): string { return root.status; }
        function toggle(): void { root.toggle(); }
        function enable(): void { root.setEnabled(true); }
        function disable(): void { root.setEnabled(false); }
        function recover(): void { root.setEnabled(false); }
    }
}
