pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // Sampling runs only while a visible view holds a reference.
    property int consumers: 0

    readonly property int historyLength: 30
    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property real downloadTotal: 0
    property real uploadTotal: 0
    property list<var> downloadHistory: []
    property list<var> uploadHistory: []
    property real previousDownload: 0
    property real previousUpload: 0
    property real previousTimestamp: 0

    function formatBytes(value: real): var {
        const units = ["B", "KiB", "MiB", "GiB", "TiB"];
        let amount = Math.max(0, value);
        let index = 0;
        while (amount >= 1024 && index < units.length - 1) {
            amount /= 1024;
            index++;
        }
        return { value: amount, unit: units[index] };
    }

    function formatBytesRate(value: real): var { return formatBytes(value) }

    function readStats(raw: string): void {
        let download = 0;
        let upload = 0;
        for (const line of raw.split("\n").slice(2)) {
            const fields = line.trim().split(/\s+/);
            if (fields.length < 9 || fields[0].startsWith("lo:"))
                continue;
            download += Number(fields[1]) || 0;
            upload += Number(fields[9]) || 0;
        }
        const now = Date.now();
        const elapsed = root.previousTimestamp > 0 ? Math.max(0.1, (now - root.previousTimestamp) / 1000) : 1;
        root.downloadSpeed = Math.max(0, (download - root.previousDownload) / elapsed);
        root.uploadSpeed = Math.max(0, (upload - root.previousUpload) / elapsed);
        root.downloadTotal = download;
        root.uploadTotal = upload;
        root.previousDownload = download;
        root.previousUpload = upload;
        root.previousTimestamp = now;
        root.downloadHistory = root.downloadHistory.concat([root.downloadSpeed]).slice(-root.historyLength);
        root.uploadHistory = root.uploadHistory.concat([root.uploadSpeed]).slice(-root.historyLength);
    }

    // startup inventory: cortetsu:network-usage-probe (on-demand dashboard telemetry)
    Process {
        id: probe
        command: ["cat", "/proc/net/dev"]
        stdout: StdioCollector { onStreamFinished: root.readStats(text) }
    }

    Timer {
        running: root.consumers > 0
        triggeredOnStart: true
        repeat: true
        interval: 2000
        onTriggered: probe.running = true
    }
}
