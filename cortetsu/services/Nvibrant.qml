pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// NVIDIA Digital Vibrance for Wayland. The helper owns the external command
// so the settings UI never has to assemble a shell command or guess support.
Singleton {
    id: root

    property int value: 0
    property bool available: false
    property bool busy: false
    property string error: ""

    readonly property Process readProcess: Process {
        command: ["nvibrant"]
        running: false
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/Set vibrance \(\s*(-?\d+)\s*\)/);
                if (match) {
                    root.value = Math.max(0, Math.min(1024, Number(match[1])));
                    root.available = true;
                    root.error = "";
                } else if (!root.available) {
                    root.error = qsTr("nvibrant no devolvió un display compatible");
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0 && !root.available)
                    root.error = text.trim().split("\n")[0];
            }
        }
        onExited: root.busy = false
    }

    readonly property Process writeProcess: Process {
        command: ["nvibrant", "0", String(root.pendingValue)]
        running: false
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim().length > 0)
                    root.error = text.trim().split("\n")[0];
            }
        }
        onExited: {
            root.busy = false;
            if (exitCode === 0) {
                root.value = root.pendingValue;
                root.available = true;
                root.error = "";
            }
        }
    }

    property int pendingValue: 0

    function reload(): void {
        if (busy)
            return;
        busy = true;
        readProcess.running = true;
    }

    function setValue(nextValue: real): void {
        if (busy || !available)
            return;
        pendingValue = Math.max(0, Math.min(1024, Math.round(nextValue)));
        busy = true;
        writeProcess.running = true;
    }

    Component.onCompleted: reload()
}
