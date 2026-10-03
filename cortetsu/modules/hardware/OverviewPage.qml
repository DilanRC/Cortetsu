pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "summary"
import "Format.js" as Format
import "Health.js" as Health

// Summary of the machine. Top to bottom: the verdict, what is working now
// (load, with recent history) beside what is filling up (capacity), and a
// last line of context. Every block opens the page that explains it.
Item {
    id: root

    required property var snapshot
    required property string status
    required property var sampleTime
    required property var cpuHistory
    required property int historyLength
    required property int historySeconds
    required property string powerProfile
    required property var pageLabels

    signal pageRequested(string target)
    signal retryRequested()

    readonly property bool hasReading: Health.hasReading(root.snapshot)
    readonly property var health: Health.evaluate(root.snapshot)
    readonly property var memory: root.snapshot?.memory ?? ({})
    readonly property var disk: root.snapshot?.disk ?? ({})
    readonly property var battery: root.snapshot?.battery ?? ({})
    readonly property var network: root.snapshot?.network ?? ({})
    readonly property var gpus: root.snapshot?.gpus ?? []
    readonly property var fans: root.snapshot?.fans ?? []

    function severityOf(id): string {
        for (const issue of root.health.issues) {
            if (issue.id === id)
                return issue.severity;
        }
        return "";
    }

    function powerText(): string {
        const profiles = {
            "power-saver": qsTr("Ahorro"),
            "balanced": qsTr("Equilibrado"),
            "performance": qsTr("Rendimiento")
        };
        if (!root.battery?.present)
            return Format.join([profiles[root.powerProfile] ?? "", qsTr("Sin batería")]);
        const states = {
            "Charging": qsTr("cargando"),
            "Discharging": qsTr("en uso"),
            "Full": qsTr("cargada"),
            "Not charging": qsTr("conectada")
        };
        return Format.join([
            profiles[root.powerProfile] ?? "",
            Format.join([qsTr("Batería"), Format.percent(root.battery.percent)], " "),
            states[root.battery.status] ?? "",
            Number(root.battery.power_w ?? 0) > 0 ? Format.watts(root.battery.power_w) : ""
        ]);
    }

    function networkText(): string {
        if (!root.network?.interface)
            return qsTr("Sin conexión");
        const down = Format.fixed(root.network.rx_mbps, 1);
        const up = Format.fixed(root.network.tx_mbps, 1);
        return Format.join([
            root.network.ssid || root.network.interface,
            down && up ? qsTr("baja %1 · sube %2 Mb/s").arg(down).arg(up) : ""
        ]);
    }

    function coolingText(): string {
        return root.fans.length === 0
            ? qsTr("Sin sensores de ventilador")
            : qsTr("%1 RPM").arg(root.fans.map(fan => fan.rpm).join(" · "));
    }

    // Exists only without a reading: its loading icon spins for as long as
    // the item does, visible or not.
    Loader {
        anchors.centerIn: parent
        active: !root.hasReading

        sourceComponent: Column {
            spacing: CortetsuDesign.spacingComfortable

            CortetsuStateMessage {
                objectName: "overviewState"
                anchors.horizontalCenter: parent.horizontalCenter
                width: 360
                kind: root.status === "error" ? "error" : "loading"
                title: root.status === "error" ? qsTr("No se pudo leer el equipo") : qsTr("Leyendo el equipo…")
                detail: root.status === "error"
                    ? qsTr("La sonda de hardware no devolvió datos. Las demás páginas que dependen de ella tampoco tendrán lecturas.")
                    : ""
            }

            CortetsuButton {
                objectName: "overviewRetry"
                anchors.horizontalCenter: parent.horizontalCenter
                visible: root.status === "error"
                disabled: root.status !== "error"
                icon: "refresh"
                label: qsTr("Reintentar")
                onClicked: root.retryRequested()
            }
        }
    }

    Column {
        id: layout
        anchors.fill: parent
        visible: root.hasReading
        spacing: CortetsuDesign.spacingStandard

        HealthBanner {
            id: banner
            width: parent.width
            health: root.health
            snapshot: root.snapshot
            status: root.status
            sampleTime: root.sampleTime
            pageLabels: root.pageLabels
            onPageRequested: target => root.pageRequested(target)
            onRetryRequested: root.retryRequested()
        }

        Row {
            id: main
            width: parent.width
            height: parent.height - banner.height - context.height - layout.spacing * 2
            spacing: CortetsuDesign.spacingStandard
            // A reading that stopped updating stays visible, but no longer
            // looks current.
            opacity: root.status === "stale" ? 0.55 : 1

            Column {
                id: load
                width: Math.round((parent.width - parent.spacing) * 0.58)
                height: parent.height
                spacing: CortetsuDesign.spacingStandard

                CpuBlock {
                    objectName: "cpuBlock"
                    width: parent.width
                    height: parent.height - gpuRows.height - (gpuRows.height > 0 ? parent.spacing : 0)
                    cpu: root.snapshot?.cpu ?? ({})
                    load: root.snapshot?.load ?? []
                    history: root.cpuHistory
                    historyLength: root.historyLength
                    historySeconds: root.historySeconds
                    temperatureSeverity: root.severityOf("cpu-temp")
                    destination: root.pageLabels.performance
                    onActivated: root.pageRequested("performance")
                }

                Column {
                    id: gpuRows
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    Repeater {
                        objectName: "gpuRows"
                        // Index-based: a row exists per GPU and outlives every
                        // reading.
                        model: root.gpus.length

                        delegate: GpuRow {
                            required property int index

                            width: gpuRows.width
                            gpu: root.gpus[index] ?? ({})
                            temperatureSeverity: root.severityOf(`gpu-temp-${index}`)
                            destination: root.pageLabels.performance
                            onActivated: root.pageRequested("performance")
                        }
                    }
                }
            }

            Column {
                id: capacity
                width: parent.width - load.width - parent.spacing
                height: parent.height
                spacing: CortetsuDesign.spacingStandard

                // Below this height the process list would lose its rows, so
                // the two levels share one line instead.
                readonly property bool tight: capacity.height < 402
                readonly property real levelWidth: capacity.tight ? (levels.width - levels.spacing) / 2 : levels.width

                Grid {
                    id: levels
                    width: parent.width
                    columns: capacity.tight ? 2 : 1
                    spacing: CortetsuDesign.spacingStandard

                    CapacityBlock {
                        objectName: "memoryBlock"
                        width: capacity.levelWidth
                        icon: "developer_board"
                        title: qsTr("Memoria")
                        usage: root.memory.usage
                        amount: Format.ratioGib(root.memory.used_gb, root.memory.total_gb)
                        severity: root.severityOf("memory")
                        footnote: Format.join([
                            Format.gib(root.memory.available_gb) ? qsTr("%1 disponibles").arg(Format.gib(root.memory.available_gb)) : "",
                            Number(root.memory.swap_total_gb ?? 0) > 0
                                ? qsTr("swap %1").arg(Format.ratioGib(root.memory.swap_used_gb, root.memory.swap_total_gb))
                                : ""
                        ])
                        destination: root.pageLabels.performance
                        onActivated: root.pageRequested("performance")
                    }

                    CapacityBlock {
                        objectName: "diskBlock"
                        width: capacity.levelWidth
                        icon: "hard_drive"
                        title: qsTr("Disco")
                        usage: root.disk.usage
                        amount: Format.ratioGib(root.disk.used_gb, root.disk.total_gb, 0)
                        severity: root.severityOf("disk")
                        footnote: Format.join([
                            Format.gib(root.disk.free_gb, 0) ? qsTr("%1 libres").arg(Format.gib(root.disk.free_gb, 0)) : "",
                            root.snapshot?.disk_io?.device ?? ""
                        ])
                        destination: root.pageLabels.io
                        onActivated: root.pageRequested("io")
                    }
                }

                ProcessBlock {
                    objectName: "processBlock"
                    width: parent.width
                    height: parent.height - levels.height - parent.spacing
                    processes: root.snapshot?.processes ?? []
                    memoryTotalGb: root.memory.total_gb
                    destination: root.pageLabels.processes
                    onActivated: root.pageRequested("processes")
                }
            }
        }

        Row {
            id: context
            width: parent.width
            height: 56
            spacing: CortetsuDesign.spacingStandard
            opacity: main.opacity

            // The network line carries a name and two rates, so it gets the
            // widest share.
            readonly property real available: context.width - context.spacing * 2

            ContextLink {
                objectName: "powerLink"
                width: Math.floor(context.available * 0.31)
                height: parent.height
                icon: root.battery?.present ? "battery_full" : "bolt"
                title: qsTr("Energía")
                value: root.powerText()
                destination: root.pageLabels.power
                onActivated: root.pageRequested("power")
            }

            ContextLink {
                objectName: "networkLink"
                width: Math.floor(context.available * 0.41)
                height: parent.height
                icon: root.network?.interface ? "lan" : "signal_disconnected"
                title: qsTr("Red")
                value: root.networkText()
                destination: root.pageLabels.io
                onActivated: root.pageRequested("io")
            }

            ContextLink {
                objectName: "coolingLink"
                width: Math.floor(context.available * 0.28)
                height: parent.height
                icon: "mode_fan"
                title: qsTr("Refrigeración")
                value: root.coolingText()
                destination: root.pageLabels.sensors
                onActivated: root.pageRequested("sensors")
            }
        }
    }
}
