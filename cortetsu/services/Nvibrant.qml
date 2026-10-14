pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// NVIDIA Digital Vibrance for the output wired to the dGPU. nvibrant cannot
// read a value: a bare call resets every display to 0. cortetsu-nvibrant owns
// the tool, reads capability from sysfs without waking the dGPU and keeps the
// profile the hotplug service reapplies, so this service never runs nvibrant
// to inspect state.
Singleton {
    id: root

    readonly property int minimum: -1024
    readonly property int maximum: 1023
    // A connected NVIDIA output exists; vibrance has nowhere to go otherwise.
    property bool available: false
    property string connector: ""
    // Last value nvibrant confirmed for the connector. Unknown until this
    // session or the hotplug service applied one.
    property bool known: false
    property int value: 0
    property int requested: 0
    property bool busy: false
    property bool writeQueued: false
    // A failed write stays visible until a later write succeeds; a status
    // refresh does not hide it.
    property string writeError: ""
    property string statusError: ""
    readonly property string error: writeError || statusError

    // startup inventory: cortetsu:nvibrant-status
    readonly property Process statusProcess: Process {
        command: ["cortetsu-nvibrant", "status"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyStatus(text)
        }
        onExited: exitCode => {
            if (exitCode !== 0 && !root.statusError.length)
                root.statusError = qsTr("No se pudo consultar la salida NVIDIA");
        }
    }

    readonly property Process writeProcess: Process {
        property string sentConnector: ""
        property int sentValue: 0
        command: ["cortetsu-nvibrant", "set", sentConnector, String(sentValue)]
        running: false
        stdout: StdioCollector {
            onStreamFinished: root.applyWrite(text)
        }
        onExited: {
            root.busy = false;
            const again = root.writeQueued && root.requested !== root.writeProcess.sentValue;
            root.writeQueued = false;
            if (again)
                root.startWrite();
        }
    }

    function parse(text: string): var {
        try {
            return JSON.parse(text);
        } catch (error) {
            return null;
        }
    }

    function applyStatus(text: string): void {
        const status = parse(text);
        if (!status?.ok) {
            available = false;
            statusError = status?.error ?? qsTr("cortetsu-nvibrant devolvió un estado ilegible");
            return;
        }
        const output = (status.outputs ?? []).find(item => item.connected) ?? null;
        available = !!output;
        connector = output?.connector ?? "";
        known = output !== null && Number.isInteger(output.value);
        if (known)
            value = output.value;
        if (!busy)
            requested = value;
        statusError = status.conflict
            ? qsTr("%1 también fija la vibrance al iniciar sesión; desactívala para que este valor se mantenga").arg(status.conflict)
            : "";
    }

    function applyWrite(text: string): void {
        const result = parse(text);
        if (result?.ok && Number.isInteger(result.value)) {
            value = result.value;
            known = true;
            writeError = "";
            return;
        }
        writeError = result?.error ?? qsTr("nvibrant no confirmó el cambio");
        // The output may have been unplugged under the slider.
        if (result?.code === "connector-disconnected" || result?.code === "connector-unknown")
            reload();
    }

    function reload(): void {
        if (!statusProcess.running)
            statusProcess.running = true;
    }

    function startWrite(): void {
        busy = true;
        writeProcess.sentConnector = connector;
        writeProcess.sentValue = requested;
        writeProcess.running = true;
    }

    function setValue(nextValue: real): void {
        if (!available)
            return;
        requested = Math.max(minimum, Math.min(maximum, Math.round(nextValue)));
        // A slider drag outruns nvibrant; keep only the latest value.
        if (busy)
            writeQueued = true;
        else
            startWrite();
    }

    Connections {
        target: Quickshell
        function onScreensChanged(): void { root.reload(); }
    }

    Component.onCompleted: reload()
}
