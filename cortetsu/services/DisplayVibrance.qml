pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Saturation per output through the screen shader Hyprland runs on every
// output, whatever GPU drives it. cortetsu-display-vibrance keeps the profile
// and regenerates the shader; the startup hook and hotplug reapply it.
Singleton {
    id: root

    property int minimum: -100
    property int maximum: 100
    property int defaultValue: 16
    // The live screen shader is the generated one. False means hypr-user.lua
    // or another tool set a different shader, so a change would not show.
    property bool active: false
    property var values: ({})
    property bool busy: false
    // Latest unsent value per output. A slider drag outruns the shader
    // rebuild, and moving to another output mid-write must not drop the first.
    property var pending: ({})
    property string writeError: ""
    property string statusError: ""
    readonly property string error: writeError || statusError

    function valueFor(name: string): int {
        return values[name] ?? defaultValue;
    }

    function hasOutput(name: string): bool {
        return values[name] !== undefined;
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    // startup inventory: cortetsu:display-vibrance-status
    readonly property Process statusProcess: Process {
        command: ["cortetsu-display-vibrance", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    readonly property Process writeProcess: Process {
        property string sentName: ""
        property int sentValue: 0
        command: ["cortetsu-display-vibrance", "set", sentName, String(sentValue)]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyWrite(text)
        }
        onExited: root.writeFinished()
        // A helper that cannot start never emits exited. Deferred, so a
        // normal exit is handled by onExited first.
        onRunningChanged: if (!running) Qt.callLater(root.writeNeverRan)
    }

    // A status read that arrived during a write was not applied.
    property bool statusStale: false

    function writeFinished(): void {
        busy = false;
        startWrite();
        if (!busy && statusStale) {
            statusStale = false;
            reload();
        }
    }

    function writeNeverRan(): void {
        if (!busy || writeProcess.running)
            return;
        writeError = qsTr("No se pudo ejecutar cortetsu-display-vibrance");
        statusStale = true;
        writeFinished();
    }

    function applyStatus(text: string): void {
        const status = parse(text);
        if (!status?.ok) {
            statusError = status?.error ?? qsTr("cortetsu-display-vibrance devolvió un estado ilegible");
            return;
        }
        minimum = status.minimum;
        maximum = status.maximum;
        defaultValue = status.default;
        active = status.active === true;
        const next = {};
        for (const output of status.outputs ?? [])
            next[output.name] = output.value;
        // Values not yet written win over what the profile still says; the
        // read is repeated once the queue drains (a hotplug mid-drag).
        if (!busy && Object.keys(pending).length === 0)
            values = next;
        else
            statusStale = true;
        statusError = "";
    }

    function applyWrite(text: string): void {
        const result = parse(text);
        // `values` already holds what was asked for (setValue), and a newer
        // value for the same output may be in flight: an accepted write
        // changes nothing there.
        if (result?.ok) {
            active = true;
            writeError = "";
            return;
        }
        writeError = result?.error ?? qsTr("No se pudo aplicar la saturación");
        // Back to what the profile holds, once nothing else is being written.
        if (busy)
            statusStale = true;
        else
            reload();
    }

    function reload(): void {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function startWrite(): void {
        const name = Object.keys(pending)[0];
        if (busy || name === undefined)
            return;
        const rest = Object.assign({}, pending);
        writeProcess.sentName = name;
        writeProcess.sentValue = rest[name];
        delete rest[name];
        pending = rest;
        busy = true;
        writeProcess.running = true;
    }

    function setValue(name: string, nextValue: real): void {
        if (!hasOutput(name))
            return;
        const clamped = Math.max(minimum, Math.min(maximum, Math.round(nextValue)));
        const queued = Object.assign({}, pending);
        queued[name] = clamped;
        pending = queued;
        const next = Object.assign({}, values);
        next[name] = clamped;
        values = next;
        startWrite();
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void { root.reload(); }
    }

    Component.onCompleted: reload()
}
