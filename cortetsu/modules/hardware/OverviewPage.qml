pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var snapshot

    property bool cpuNumeric: false
    property bool memoryNumeric: true

    readonly property var cpu: snapshot?.cpu ?? ({})
    readonly property var memory: snapshot?.memory ?? ({})
    readonly property var disk: snapshot?.disk ?? ({})
    readonly property var battery: snapshot?.battery ?? ({})
    readonly property var network: snapshot?.network ?? ({})
    readonly property var gpus: snapshot?.gpus ?? []
    readonly property var fans: snapshot?.fans ?? []

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function pct(value): string { return `${number(value, 1)}%`; }
    function temp(value): string { return value === null || value === undefined ? "—" : `${number(value, 1)} °C`; }
    function gb(value): string { return value === null || value === undefined ? "—" : `${number(value, 2)} GiB`; }
    function watt(value): string { return value === null || value === undefined ? "—" : `${number(value, 1)} W`; }
    function speed(value): string { return value === null || value === undefined ? "—" : `${number(value, 2)} Mb/s`; }

    function cpuHeadline(): string {
        if (!cpuNumeric)
            return pct(cpu?.usage);
        const mhz = Number(cpu?.freq_mhz ?? 0);
        return mhz > 0 ? `${number(mhz / 1000, 2)} GHz` : "—";
    }

    function memoryHeadline(): string {
        return memoryNumeric ? gb(memory?.used_gb) : pct(memory?.usage);
    }

    function gpuAt(index): var {
        return index >= 0 && index < gpus.length ? gpus[index] : ({});
    }

    Grid {
        id: cards
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        columns: 2
        columnSpacing: CortetsuDesign.spacingStandard
        rowSpacing: CortetsuDesign.spacingStandard

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: qsTr("CPU")
            icon: "memory"
            headline: root.cpuHeadline()
            subtitle: root.cpuNumeric
                ? `${root.pct(root.cpu?.usage)} · ${root.cpu?.model ?? "CPU"}`
                : (root.cpu?.model ?? "CPU")
            progress: Number(root.cpu?.usage ?? 0) / 100
            modeLabel: root.cpuNumeric ? "GHz" : "%"
            onModeRequested: root.cpuNumeric = !root.cpuNumeric
            rows: [
                { label: qsTr("Temperature"), value: root.temp(root.cpu?.temp_c) },
                { label: qsTr("Frequency"), value: root.cpu?.freq_mhz ? `${root.number(root.cpu.freq_mhz, 0)} MHz` : "—" },
                { label: qsTr("Governor"), value: root.cpu?.governor ?? "—" }
            ]
        }

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: qsTr("Memory")
            icon: "developer_board"
            headline: root.memoryHeadline()
            subtitle: root.memoryNumeric
                ? `${root.gb(root.memory?.total_gb)} total · ${root.pct(root.memory?.usage)}`
                : `${root.gb(root.memory?.used_gb)} / ${root.gb(root.memory?.total_gb)}`
            progress: Number(root.memory?.usage ?? 0) / 100
            modeLabel: root.memoryNumeric ? "GiB" : "%"
            onModeRequested: root.memoryNumeric = !root.memoryNumeric
            rows: [
                { label: qsTr("Used"), value: root.gb(root.memory?.used_gb) },
                { label: qsTr("Available"), value: root.gb(Math.max(0, Number(root.memory?.total_gb ?? 0) - Number(root.memory?.used_gb ?? 0))) },
                { label: qsTr("Swap"), value: `${root.gb(root.memory?.swap_used_gb)} / ${root.gb(root.memory?.swap_total_gb)}` }
            ]
        }

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: qsTr("Storage")
            icon: "hard_drive"
            headline: root.pct(root.disk?.usage)
            subtitle: `${root.gb(root.disk?.used_gb)} / ${root.gb(root.disk?.total_gb)}`
            progress: Number(root.disk?.usage ?? 0) / 100
            rows: [
                { label: qsTr("Used"), value: root.gb(root.disk?.used_gb) },
                { label: qsTr("Free"), value: root.gb(root.disk?.free_gb) },
                { label: qsTr("Device"), value: root.snapshot?.disk_io?.device ?? "/" }
            ]
        }

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: root.gpuAt(0)?.vendor ? `${root.gpuAt(0).vendor} GPU` : qsTr("GPU")
            icon: "view_in_ar"
            headline: root.gpus.length > 0 ? root.pct(root.gpuAt(0)?.usage) : qsTr("Not detected")
            subtitle: root.gpuAt(0)?.name ?? qsTr("No GPU telemetry")
            progress: root.gpus.length > 0 ? Number(root.gpuAt(0)?.usage ?? 0) / 100 : -1
            rows: [
                { label: qsTr("Temperature"), value: root.temp(root.gpuAt(0)?.temp_c) },
                { label: qsTr("VRAM"), value: `${root.gb(root.gpuAt(0)?.vram_used_gb)} / ${root.gb(root.gpuAt(0)?.vram_total_gb)}` },
                { label: qsTr("Power"), value: root.watt(root.gpuAt(0)?.power_w) }
            ]
        }

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: root.gpus.length > 1
                ? (root.gpuAt(1)?.vendor ? `${root.gpuAt(1).vendor} GPU` : qsTr("GPU 2"))
                : qsTr("Network")
            icon: root.gpus.length > 1 ? "sports_esports" : "wifi"
            headline: root.gpus.length > 1
                ? root.pct(root.gpuAt(1)?.usage)
                : (root.network?.interface ?? "—")
            subtitle: root.gpus.length > 1
                ? (root.gpuAt(1)?.name ?? qsTr("Second GPU"))
                : `${qsTr("Down")} ${root.speed(root.network?.rx_mbps)}`
            progress: root.gpus.length > 1 ? Number(root.gpuAt(1)?.usage ?? 0) / 100 : -1
            rows: root.gpus.length > 1
                ? [
                    { label: qsTr("Temperature"), value: root.temp(root.gpuAt(1)?.temp_c) },
                    { label: qsTr("VRAM"), value: `${root.gb(root.gpuAt(1)?.vram_used_gb)} / ${root.gb(root.gpuAt(1)?.vram_total_gb)}` },
                    { label: qsTr("Power"), value: root.watt(root.gpuAt(1)?.power_w) }
                ]
                : [
                    { label: qsTr("Down"), value: root.speed(root.network?.rx_mbps) },
                    { label: qsTr("Up"), value: root.speed(root.network?.tx_mbps) },
                    { label: qsTr("Interface"), value: root.network?.interface ?? "—" }
                ]
        }

        MetricCard {
            width: (cards.width - cards.columnSpacing) / 2
            title: root.battery?.present ? qsTr("Battery") : qsTr("System")
            icon: root.battery?.present ? "battery_charging_full" : "monitor_heart"
            headline: root.battery?.present ? root.pct(root.battery?.percent) : (root.cpu?.cores ? `${root.cpu.cores} cores` : "—")
            subtitle: root.battery?.present ? (root.battery?.status ?? "—") : qsTr("Current host state")
            progress: root.battery?.present ? Number(root.battery?.percent ?? 0) / 100 : -1
            rows: root.battery?.present
                ? [
                    { label: qsTr("Power"), value: root.watt(root.battery?.power_w) },
                    { label: qsTr("Network"), value: root.network?.interface ?? "—" },
                    { label: qsTr("Down / Up"), value: `${root.speed(root.network?.rx_mbps)} / ${root.speed(root.network?.tx_mbps)}` }
                ]
                : [
                    { label: qsTr("Load 1m"), value: root.snapshot?.load?.length ? root.number(root.snapshot.load[0], 2) : "—" },
                    { label: qsTr("Cooling"), value: root.fans.length > 0 ? `${root.fans.length} fans` : qsTr("Passive") },
                    { label: qsTr("Network"), value: root.network?.interface ?? "—" }
                ]
        }
    }

    Row {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: cards.bottom
        anchors.topMargin: CortetsuDesign.spacingComfortable
        height: 54
        spacing: CortetsuDesign.spacingStandard

        SummaryStat {
            width: (parent.width - parent.spacing * 3) / 4
            label: qsTr("Cooling")
            value: root.fans.length > 0
                ? root.fans.map(f => `${f.rpm} RPM`).join(" · ")
                : qsTr("No fan telemetry")
        }

        SummaryStat {
            width: (parent.width - parent.spacing * 3) / 4
            label: qsTr("System load")
            value: root.snapshot?.load?.length
                ? `${root.number(root.snapshot.load[0], 2)} · ${root.number(root.snapshot.load[1], 2)} · ${root.number(root.snapshot.load[2], 2)}`
                : "—"
        }

        SummaryStat {
            width: (parent.width - parent.spacing * 3) / 4
            label: qsTr("Network totals")
            value: `${qsTr("RX")} ${root.gb(root.network?.rx_total_gb)} · ${qsTr("TX")} ${root.gb(root.network?.tx_total_gb)}`
        }

        SummaryStat {
            width: (parent.width - parent.spacing * 3) / 4
            label: qsTr("Threads")
            value: `${root.cpu?.cores ?? 0} ${qsTr("logical")}`
        }
    }

    component SummaryStat: Column {
        required property string label
        required property string value
        spacing: 3

        CortetsuText {
            width: parent.width
            text: parent.value
            color: CortetsuDesign.colorOnSurface
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            width: parent.width
            text: parent.label
            color: CortetsuDesign.colorOutline
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }
    }
}
