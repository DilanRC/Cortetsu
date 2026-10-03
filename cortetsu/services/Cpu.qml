pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property string name: "CPU"
    property real percentage: 0
    property real temperature: 0
    property real previousTotal: 0
    property real previousIdle: 0

    function readStats(raw: string): void {
        const line = raw.split("\n").find(value => value.startsWith("cpu "));
        if (!line)
            return;
        const values = line.trim().split(/\s+/).slice(1).map(Number);
        const idle = (values[3] ?? 0) + (values[4] ?? 0);
        const total = values.reduce((sum, value) => sum + (Number.isFinite(value) ? value : 0), 0);
        const deltaTotal = total - root.previousTotal;
        const deltaIdle = idle - root.previousIdle;
        if (root.previousTotal > 0 && deltaTotal > 0)
            root.percentage = Math.max(0, Math.min(1, 1 - deltaIdle / deltaTotal));
        root.previousTotal = total;
        root.previousIdle = idle;
    }

    FileView {
        id: cpuInfo
        path: "/proc/cpuinfo"
        onLoaded: {
            const model = text().split("\n").find(line => line.startsWith("model name"));
            if (model)
                root.name = model.split(":").slice(1).join(":").trim() || root.name;
        }
    }

    FileView {
        id: cpuStats
        path: "/proc/stat"
        onLoaded: root.readStats(text())
    }

    // startup inventory: cortetsu:cpu-temperature (on-demand resource view)
    Process {
        id: temperature
        command: ["sh", "-c", "for f in /sys/class/thermal/thermal_zone*/temp; do [ -r \"$f\" ] && cat \"$f\" && break; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const value = Number(text.trim());
                if (Number.isFinite(value))
                    root.temperature = value > 1000 ? value / 1000 : value;
            }
        }
    }

    Timer {
        running: true
        repeat: true
        interval: 2000
        onTriggered: {
            cpuStats.reload();
            temperature.running = true;
        }
    }
}
