pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Client of the Rust playback supervisor (`cortetsu-orbital session`).
// The supervisor owns renderers, per-monitor ownership and orbital.json; this
// singleton only relays requests and mirrors its snapshots. It starts on
// demand (Steam library opened) or when orbital.json asks to restore a
// wallpaper at login, never otherwise.
Singleton {
    id: root

    property var outputs: ({})
    property var preferences: ({ monitors: {}, previous: {}, favorites: [], collections: {}, playlists: {}, profiles: {}, libraryRoots: [] })
    property var backends: []
    // location -> verdict from the backend: {supported, capabilities | code, message}
    property var inspections: ({})
    property string error: ""
    property string errorCode: ""
    property bool available: false
    property bool steamRequested: false
    property int failures: 0
    // A context that holds animated wallpapers keeps the static cover on
    // every monitor until it is deactivated (CortetsuContexts owns it).
    readonly property bool hold: CortetsuContexts.orbitalHold
    // The theme colours taken from an animated wallpaper's preview.
    // "" | "busy" | "applied" | "refused" (Smart scheme off or a manual
    // scheme chosen) | "error". The colour daemon keeps them while the
    // renderer runs and returns to the static wallpaper's when it stops.
    property string colourState: ""
    property string colourError: ""
    // The preview the state above belongs to: another wallpaper's panel
    // must not show this one's result.
    property string colourPreview: ""
    function adoptColours(preview: string): bool {
        if (colourProcess.running || !preview)
            return false;
        colourPreview = preview;
        colourState = "busy";
        colourError = "";
        colourProcess.command = ["cortetsu-apply-wallpaper-colors", preview];
        colourProcess.running = true;
        return true;
    }
    onHoldChanged: if (available) heartbeat()
    function heartbeat(): void { send({ op: "heartbeat", battery: CortetsuPower.onBattery, hold }); }
    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/orbital.json`

    function output(monitor: string): var { return outputs[monitor] || {}; }
    function activeOn(monitor: string): bool { return output(monitor).state === "active"; }

    function ensure(): void {
        if (worker.running || restartTimer.running) return;
        failures = 0;
        worker.running = true;
    }
    function send(message: var): bool {
        if (!available) {
            error = qsTr("El supervisor de Orbital no está disponible.");
            errorCode = "unavailable";
            return false;
        }
        worker.write(JSON.stringify(message) + "\n");
        return true;
    }
    function apply(monitor: string, selection: var): bool {
        error = "";
        errorCode = "";
        return send({ op: "apply", monitor, selection });
    }
    function inspect(location: string): void {
        if (location && available) send({ op: "inspect", location });
    }
    function requestSteam(): void {
        steamRequested = true;
        ensure();
    }
    function takeSteamRequest(): bool {
        const requested = steamRequested;
        steamRequested = false;
        return requested;
    }

    function consume(line: string): void {
        let message;
        try {
            message = JSON.parse(line);
        } catch (_) {
            error = qsTr("Respuesta no válida del supervisor.");
            return;
        }
        if (message.event === "error") {
            error = message.message;
            errorCode = message.code || "";
        } else if (message.event === "inspection") {
            const next = Object.assign({}, inspections);
            next[message.location] = Object.assign({ available: message.available }, message.verdict);
            inspections = next;
        } else if (message.event === "snapshot") {
            available = true;
            outputs = message.outputs;
            preferences = message.preferences;
            backends = message.backends || [];
        }
    }

    // Before the supervisor runs, orbital.json still feeds library folders and
    // decides whether a login restore is due.
    FileView {
        path: root.statePath
        printErrors: false
        onLoaded: {
            let saved;
            try { saved = JSON.parse(text()); } catch (_) { return; }
            if (!root.available) root.preferences = Object.assign({}, root.preferences, saved);
            const monitors = Object.values(saved.monitors || {});
            if (monitors.some(s => s.restoreOnStart !== false)) root.ensure();
        }
    }

    // startup inventory: cortetsu:orbital-colours (on request only)
    Process {
        id: colourProcess
        stderr: StdioCollector { id: colourDiagnostics }
        onExited: code => {
            root.colourState = code === 0 ? "applied" : code === 3 ? "refused" : "error";
            root.colourError = code === 0 || code === 3 ? "" : colourDiagnostics.text.trim().slice(-400);
        }
    }

    // startup inventory: cortetsu:orbital-supervisor (Steam library or saved restore)
    Process {
        id: worker
        command: [Quickshell.env("HOME") + "/.local/bin/cortetsu-orbital", "session"]
        stdinEnabled: true
        stdout: SplitParser { onRead: data => root.consume(data) }
        stderr: StdioCollector { id: diagnostics }
        onExited: (code, status) => {
            root.available = false;
            root.outputs = ({});
            root.inspections = ({});
            if (code === 0) return;
            root.failures += 1;
            root.error = diagnostics.text.trim() || qsTr("Orbital se cerró de forma inesperada.");
            root.errorCode = "supervisor";
            // Renderers die with the supervisor and the static wallpaper stays.
            // Two retries cover a reload racing the previous instance's lock.
            if (root.failures <= 2) restartTimer.start();
            else root.error += "\n" + qsTr("Se conserva el fondo estático; Orbital no se reiniciará solo.");
        }
    }
    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: worker.running = true
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.available
        triggeredOnStart: true
        onTriggered: root.heartbeat()
    }

    // Scripted QA, the same actions as the panel: what a monitor shows, and
    // replay its saved animated wallpaper with the battery pause on or off.
    IpcHandler {
        target: "orbital"
        function state(monitor: string): string { return JSON.stringify(root.output(monitor)); }
        // Play on `monitor` what `source` has saved (as choosing it there in
        // the panel would).
        function copy(source: string, monitor: string): bool {
            const saved = root.preferences.monitors?.[source];
            if (!saved?.location)
                return false;
            root.ensure();
            return root.apply(monitor, Object.assign({}, saved));
        }
        function replay(monitor: string, pauseOnBattery: bool): bool {
            const saved = root.preferences.monitors?.[monitor];
            if (!saved?.location)
                return false;
            root.ensure();
            return root.apply(monitor, Object.assign({}, saved, { pauseOnBattery }));
        }
    }
}
