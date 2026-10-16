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
    // The NVIDIA dGPU is runtime-suspended. It is then not queried (asking
    // would wake it) and the integrated GPU that renders the desktop is shown.
    property bool dgpuAsleep: false

    // Same short model name as the Hardware Center rows.
    function model(gpu): string {
        const name = String(gpu?.name ?? "");
        const bracket = name.lastIndexOf("] ");
        return bracket >= 0 ? name.slice(bracket + 2) : name;
    }

    // startup inventory: cortetsu:gpu-probe (on-demand dashboard telemetry)
    Process {
        id: probe
        command: [StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-hardware-probe", "--gpus"]
        stdout: StdioCollector {
            onStreamFinished: {
                let gpus = [];
                try {
                    gpus = JSON.parse(text).gpus ?? [];
                } catch (error) {
                    gpus = [];
                }
                const nvidia = gpus.find(gpu => gpu.vendor === "NVIDIA");
                const shown = nvidia?.state === "active" ? nvidia : (gpus.find(gpu => gpu.vendor === "AMD") ?? null);
                root.dgpuAsleep = nvidia?.state === "suspended";
                if (!shown) {
                    root.type = root.noneType;
                    root.name = root.dgpuAsleep ? root.model(nvidia) : "";
                    root.percentage = 0;
                    root.temperature = 0;
                    return;
                }
                root.type = 1;
                root.name = root.model(shown);
                root.percentage = Math.max(0, Math.min(1, Number(shown.usage ?? 0) / 100));
                root.temperature = Number(shown.temp_c) || 0;
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
