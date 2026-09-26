pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property list<var> disks: []
    property var manualPrimaryDisk: null
    readonly property var primaryDisk: manualPrimaryDisk ?? disks[0] ?? null
    readonly property real percentage: primaryDisk?.perc ?? 0

    function readDisks(raw: string): void {
        const found = [];
        for (const line of raw.trim().split("\n").slice(1)) {
            const match = line.match(/^\S+\s+(\d+)\s+(\d+)\s+(\d+)\s+\S+\s+(.+)$/);
            if (!match)
                continue;
            const total = Number(match[1]);
            const used = Number(match[2]);
            if (!total || !match[4].startsWith("/"))
                continue;
            found.push({ mount: match[4], used, total, free: Number(match[3]), perc: used / total, hasRoot: match[4] === "/" });
        }
        root.disks = found;
        if (root.manualPrimaryDisk && !found.some(disk => disk.mount === root.manualPrimaryDisk.mount))
            root.manualPrimaryDisk = null;
    }

    Process {
        id: probe
        command: ["sh", "-c", "df -kP -x tmpfs -x devtmpfs 2>/dev/null"]
        stdout: StdioCollector { onStreamFinished: root.readDisks(text) }
    }

    Timer {
        running: true
        repeat: true
        interval: 5000
        onTriggered: probe.running = true
    }
}
