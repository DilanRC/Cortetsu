pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Sampling runs only while a visible view holds a reference.
    property int consumers: 0

    readonly property int noneType: 3
    property int type: noneType
    property string name: ""
    property real percentage: 0
    property real temperature: 0

    // startup inventory: cortetsu:gpu-probe (on-demand dashboard telemetry)
    Process {
        id: probe
        command: ["sh", "-c", "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=name,utilization.gpu,temperature.gpu --format=csv,noheader,nounits"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split(",").map(value => value.trim());
                if (parts.length < 3 || !parts[0]) {
                    root.type = root.noneType;
                    root.name = "";
                    root.percentage = 0;
                    root.temperature = 0;
                    return;
                }
                root.type = 1;
                root.name = parts[0];
                root.percentage = Math.max(0, Math.min(1, Number(parts[1]) / 100));
                root.temperature = Number(parts[2]) || 0;
            }
        }
    }

    Timer {
        running: root.consumers > 0
        triggeredOnStart: true
        repeat: true
        interval: 3000
        onTriggered: probe.running = true
    }
}
