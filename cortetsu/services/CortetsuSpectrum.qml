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
        command: ["sh", "-c", "command -v cava >/dev/null 2>&1 && exec cava"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.consume(data)
        }
    }
}
