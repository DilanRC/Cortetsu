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

    // Placeholders until the first status read; the helper owns the range.
    property int minimum: -100
    property int maximum: 100
    property int defaultValue: 16
    // The live screen shader is the generated one. False means hypr-user.lua
    // or another tool set a different shader, so a change would not show.
    property bool active: false
    property var values: ({})
    readonly property bool busy: writes.busy
    property string writeError: ""
    property string statusError: ""
    readonly property string error: writeError || statusError
    // A status read that arrived while values were still being written.
    property bool statusStale: false

    function valueFor(name: string): int {
        return values[name] ?? defaultValue;
    }

    function hasOutput(name: string): bool {
        return values[name] !== undefined;
    }

    // startup inventory: cortetsu:display-vibrance-status
    readonly property Process statusProcess: Process {
        command: ["cortetsu-display-vibrance", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
    }

    readonly property HelperWriteQueue writes: HelperWriteQueue {
        command: (name, value) => ["cortetsu-display-vibrance", "set", name, String(value)]
        startError: qsTr("No se pudo ejecutar cortetsu-display-vibrance")
        // `values` already holds what was asked for, and a newer value for
        // the same output may be waiting: an accepted write changes nothing.
        onAnswered: (name, value, result) => {
            if (result?.ok) {
                root.active = true;
                root.writeError = "";
                return;
            }
            root.writeError = result?.error ?? qsTr("No se pudo aplicar la saturación");
            root.statusStale = true;
        }
        onUnstartable: (name, value, error) => {
            root.writeError = error;
            root.statusStale = true;
        }
        // Back to what the profile holds after a failure, and the read a
        // hotplug asked for mid-drag.
        onDrained: {
            if (root.statusStale)
                root.reload();
        }
    }

    function applyStatus(text: string): void {
        let status = null;
        try {
            status = JSON.parse(text);
        } catch (error) {}
        if (!status?.ok) {
            statusError = status?.error ?? qsTr("cortetsu-display-vibrance devolvió un estado ilegible");
            return;
        }
        minimum = status.minimum;
        maximum = status.maximum;
        defaultValue = status.default;
        active = status.active === true;
        statusError = "";
        // Values not yet written win over what the profile still says.
        if (!writes.idle) {
            statusStale = true;
            return;
        }
        statusStale = false;
        const next = {};
        for (const output of status.outputs ?? [])
            next[output.name] = output.value;
        values = next;
    }

    function reload(): void {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function setValue(name: string, nextValue: real): void {
        if (!hasOutput(name))
            return;
        const clamped = Math.max(minimum, Math.min(maximum, Math.round(nextValue)));
        const next = Object.assign({}, values);
        next[name] = clamped;
        values = next;
        writes.enqueue(name, clamped);
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void { root.reload(); }
    }

    Component.onCompleted: reload()
}
