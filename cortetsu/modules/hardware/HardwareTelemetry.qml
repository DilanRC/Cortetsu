pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io

// The one source of main telemetry for Hardware Center. Pages bind to the
// reading and to `status`; none of them starts a process for this data.
Item {
    id: root

    visible: false

    // Sampling runs only while the surface that shows the data is visible.
    property bool active: false
    // The process table is about 98 % of a full sample. Only the Processes
    // page reads all of it; every other page gets the most active few.
    property bool fullProcessList: false
    readonly property int summaryProcessCount: 5

    property var snapshot: ({})
    // "loading" until the first run ends; then "live", "stale" when a run
    // failed but an older reading is still shown, or "error" when no run has
    // produced a reading yet.
    property string status: "loading"
    property string failure: ""
    property int sampleCount: 0
    readonly property bool sampling: probe.running
    readonly property var sampleTime: root.sampleCount > 0 && root.snapshot?.timestamp
        ? new Date(Number(root.snapshot.timestamp) * 1000)
        : null

    readonly property int intervalMs: 1500
    readonly property int historyLength: 80
    readonly property int historySeconds: Math.round(root.historyLength * root.intervalMs / 1000)
    property var cpuHistory: []
    property var cpuCoreHistories: []
    property var memoryUsedHistory: []
    property var memoryCacheHistory: []
    property var swapUsedHistory: []
    property var networkRxHistory: []
    property var networkTxHistory: []
    property var diskReadHistory: []
    property var diskWriteHistory: []
    property var gpu0History: []
    property var gpu1History: []

    property bool runProducedReading: false
    property bool rerunRequested: false
    property int overdueTicks: 0

    readonly property string probePath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-hardware-probe"

    function pushHistory(source, value): var {
        const next = (source ?? []).slice(1 - root.historyLength);
        next.push(Number(value ?? 0));
        return next;
    }

    function recordHistory(parsed): void {
        root.cpuHistory = pushHistory(root.cpuHistory, parsed?.cpu?.usage);

        const coreValues = parsed?.cpu?.per_core ?? [];
        const coreHistories = Array.from(root.cpuCoreHistories ?? []);
        while (coreHistories.length < coreValues.length)
            coreHistories.push([]);
        for (let i = 0; i < coreValues.length; ++i)
            coreHistories[i] = pushHistory(coreHistories[i], coreValues[i]);
        root.cpuCoreHistories = coreHistories;

        root.memoryUsedHistory = pushHistory(root.memoryUsedHistory, parsed?.memory?.used_gb);
        root.memoryCacheHistory = pushHistory(root.memoryCacheHistory, parsed?.memory?.cache_gb);
        root.swapUsedHistory = pushHistory(root.swapUsedHistory, parsed?.memory?.swap_used_gb);
        root.networkRxHistory = pushHistory(root.networkRxHistory, parsed?.network?.rx_mbps);
        root.networkTxHistory = pushHistory(root.networkTxHistory, parsed?.network?.tx_mbps);
        root.diskReadHistory = pushHistory(root.diskReadHistory, parsed?.disk_io?.read_mib_s);
        root.diskWriteHistory = pushHistory(root.diskWriteHistory, parsed?.disk_io?.write_mib_s);
        root.gpu0History = pushHistory(root.gpu0History, parsed?.gpus?.[0]?.usage);
        root.gpu1History = pushHistory(root.gpu1History, parsed?.gpus?.[1]?.usage);
    }

    function refresh(): void {
        if (!root.active)
            return;
        if (probe.running) {
            root.rerunRequested = true;
            return;
        }
        root.overdueTicks = 0;
        root.runProducedReading = false;
        root.rerunRequested = false;
        probe.running = true;
    }

    function accept(text): void {
        let parsed;
        try {
            parsed = JSON.parse(text.trim());
        } catch (error) {
            return;
        }
        if (!parsed || typeof parsed !== "object" || !parsed.cpu)
            return;
        root.runProducedReading = true;
        root.snapshot = parsed;
        root.recordHistory(parsed);
        root.sampleCount += 1;
        root.failure = "";
        root.status = "live";
    }

    function reject(reason): void {
        const next = root.sampleCount > 0 ? "stale" : "error";
        if (root.status !== next)
            console.warn(`Hardware Center: ${reason}`);
        root.failure = reason;
        root.status = next;
    }

    onFullProcessListChanged: {
        if (root.fullProcessList)
            root.refresh();
    }

    Timer {
        interval: root.intervalMs
        repeat: true
        running: root.active
        triggeredOnStart: true
        onTriggered: {
            if (!probe.running) {
                root.refresh();
                return;
            }
            // A run that outlives four intervals is hung. Ending it reports
            // the failure and lets sampling resume.
            root.overdueTicks += 1;
            if (root.overdueTicks >= 4)
                probe.running = false;
        }
    }

    // startup inventory: cortetsu:hardware-probe
    Process {
        id: probe
        command: root.fullProcessList
            ? [root.probePath]
            : [root.probePath, "--top-processes", String(root.summaryProcessCount)]

        stdout: StdioCollector {
            onStreamFinished: root.accept(text)
        }

        onRunningChanged: {
            if (running)
                return;
            if (!root.runProducedReading)
                root.reject(root.overdueTicks >= 4 ? "probe timed out" : "probe returned no reading");
            if (root.rerunRequested)
                root.refresh();
        }
    }
}
