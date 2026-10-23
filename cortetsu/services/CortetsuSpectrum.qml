pragma Singleton

import QtQml
import Quickshell.Io
import "../modules"

// Optional first-party spectrum boundary. The shell remains usable when cava
// is absent; consumers receive a stable zero-filled list instead of an
// upstream service object.
QtObject {
    id: root

    readonly property int barCount: CortetsuConfig.visualiserBars
    property list<real> values: Array(barCount).fill(0)
    property bool available: false
    // Eager singleton construction must never spawn cava while disabled.
    readonly property bool shouldRun: CortetsuConfig.visualiserEnabled
    onShouldRunChanged: if (!shouldRun) {
        root.available = false;
        root.values = Array(root.barCount).fill(0);
    }

    function consume(line: string): void {
        const parsed = line.trim().split(";")
            .map(value => Number(value))
            .filter(value => Number.isFinite(value));
        if (parsed.length === 0)
            return;
        values = parsed.slice(0, barCount).map(value => Math.max(0, Math.min(1, value / 100)));
        while (values.length < barCount)
            values.push(0);
        available = true;
    }

    // startup inventory: cortetsu:spectrum (conditional on cava availability)
    property Process cavaProcess: Process {
        // Without cava the process fails to start once and running turns false.
        command: ["cava"]
        running: root.shouldRun
        onRunningChanged: if (!running) {
            root.available = false;
            root.values = Array(root.barCount).fill(0);
        }
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.consume(data)
        }
    }
}
