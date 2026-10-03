pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var snapshot
    required property var cpuHistory
    required property var cpuCoreHistories
    required property var memoryUsedHistory
    required property var memoryCacheHistory
    required property var swapUsedHistory
    required property var networkRxHistory
    required property var networkTxHistory
    required property var diskReadHistory
    required property var diskWriteHistory
    required property var gpu0History
    required property var gpu1History

    property int selectedCpuCore: -1
    property bool showSwapHistory: false

    readonly property var cpu: snapshot?.cpu ?? ({})
    readonly property var memory: snapshot?.memory ?? ({})
    readonly property var network: snapshot?.network ?? ({})
    readonly property var diskIo: snapshot?.disk_io ?? ({})
    readonly property var gpus: snapshot?.gpus ?? []
    readonly property var selectedCpuHistory: selectedCpuCore < 0
        ? cpuHistory
        : (selectedCpuCore < cpuCoreHistories.length ? cpuCoreHistories[selectedCpuCore] : [])
    readonly property real selectedCpuNow: selectedCpuCore < 0
        ? Number(cpu?.usage ?? 0)
        : Number(cpu?.per_core?.[selectedCpuCore] ?? 0)

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function pct(value): string {
        return `${number(value, 1)}%`;
    }

    function gpuAt(index): var {
        return index >= 0 && index < gpus.length ? gpus[index] : ({});
    }

    function cycleCpu(): void {
        const count = Number(cpu?.cores ?? 0);
        if (count <= 0) {
            selectedCpuCore = -1;
            return;
        }
        selectedCpuCore = selectedCpuCore >= count - 1 ? -1 : selectedCpuCore + 1;
    }

    Grid {
        anchors.fill: parent
        columns: 2
        columnSpacing: 12
        rowSpacing: 12

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: root.selectedCpuCore < 0 ? qsTr("CPU total") : `CPU ${root.selectedCpuCore}`
            icon: "memory"
            headline: root.pct(root.selectedCpuNow)
            subtitle: `${root.number(root.cpu?.temp_c, 1)} °C · ${root.number(root.cpu?.freq_mhz, 0)} MHz · ${root.cpu?.governor ?? "—"}`
            legendA: root.selectedCpuCore < 0 ? qsTr("Total") : `Núcleo ${root.selectedCpuCore}`
            seriesA: root.selectedCpuHistory
            maxValue: 100
            unit: "%"
            actionLabel: root.selectedCpuCore < 0 ? qsTr("Total") : `C${root.selectedCpuCore}`
            onActionRequested: root.cycleCpu()
        }

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: qsTr("Memoria")
            icon: "developer_board"
            headline: `${root.number(root.memory?.used_gb, 2)} / ${root.number(root.memory?.total_gb, 2)} GiB`
            subtitle: `${qsTr("disponible")} ${root.number(root.memory?.available_gb, 2)} GiB · ${qsTr("caché")} ${root.number(root.memory?.cache_gb, 2)} · ${qsTr("intercambio")} ${root.number(root.memory?.swap_used_gb, 2)}`
            legendA: qsTr("Usada")
            legendB: root.showSwapHistory ? qsTr("Intercambio") : qsTr("Caché")
            seriesA: root.memoryUsedHistory
            seriesB: root.showSwapHistory ? root.swapUsedHistory : root.memoryCacheHistory
            maxValue: Math.max(1, Number(root.memory?.total_gb ?? 1))
            unit: "GiB"
            colourA: CortetsuDesign.colorPrimary
            colourB: root.showSwapHistory ? CortetsuDesign.colorTertiary : CortetsuDesign.colorSecondary
            actionLabel: root.showSwapHistory ? qsTr("Intercambio") : qsTr("Caché")
            onActionRequested: root.showSwapHistory = !root.showSwapHistory
        }

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: qsTr("Red")
            icon: "wifi"
            headline: `${root.number(root.network?.rx_mbps, 2)} ↓  ${root.number(root.network?.tx_mbps, 2)} ↑ Mb/s`
            subtitle: `${root.network?.interface ?? "—"} · RX ${root.number(root.network?.rx_total_gb, 2)} GiB · TX ${root.number(root.network?.tx_total_gb, 2)} GiB`
            legendA: qsTr("Descarga")
            legendB: qsTr("Subida")
            seriesA: root.networkRxHistory
            seriesB: root.networkTxHistory
            unit: "Mb/s"
            colourA: CortetsuDesign.colorPrimary
            colourB: CortetsuDesign.colorTertiary
        }

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: qsTr("E/S de disco / NVMe")
            icon: "hard_drive"
            headline: `${root.number(root.diskIo?.read_mib_s, 2)} R · ${root.number(root.diskIo?.write_mib_s, 2)} W MiB/s`
            subtitle: `${root.diskIo?.device ?? qsTr("Dispositivo raíz")} · ${root.number(root.diskIo?.read_iops, 0)} / ${root.number(root.diskIo?.write_iops, 0)} IOPS`
            legendA: qsTr("Lectura")
            legendB: qsTr("Escritura")
            seriesA: root.diskReadHistory
            seriesB: root.diskWriteHistory
            unit: "MiB/s"
            colourA: CortetsuDesign.colorSecondary
            colourB: CortetsuDesign.colorTertiary
        }

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: root.gpuAt(0)?.vendor ? `${root.gpuAt(0).vendor} ${qsTr("GPU")}` : qsTr("GPU 1")
            icon: "view_in_ar"
            headline: root.gpus.length > 0 ? root.pct(root.gpuAt(0)?.usage) : qsTr("No detectada")
            subtitle: root.gpus.length > 0
                ? `${root.number(root.gpuAt(0)?.temp_c, 1)} °C · ${root.number(root.gpuAt(0)?.power_w, 1)} W · ${root.number(root.gpuAt(0)?.vram_used_gb, 2)} / ${root.number(root.gpuAt(0)?.vram_total_gb, 2)} GiB`
                : qsTr("Sin datos")
            legendA: qsTr("Uso de GPU")
            seriesA: root.gpu0History
            maxValue: 100
            unit: "%"
            colourA: CortetsuDesign.colorPrimary
        }

        HistoryGraph {
            width: (parent.width - 12) / 2
            height: (parent.height - 24) / 3
            title: root.gpuAt(1)?.vendor ? `${root.gpuAt(1).vendor} ${qsTr("GPU")}` : qsTr("GPU 2")
            icon: "sports_esports"
            headline: root.gpus.length > 1 ? root.pct(root.gpuAt(1)?.usage) : qsTr("No detectada")
            subtitle: root.gpus.length > 1
                ? `${root.number(root.gpuAt(1)?.temp_c, 1)} °C · ${root.number(root.gpuAt(1)?.power_w, 1)} W · ${root.number(root.gpuAt(1)?.vram_used_gb, 2)} / ${root.number(root.gpuAt(1)?.vram_total_gb, 2)} GiB`
                : qsTr("Sin datos")
            legendA: qsTr("Uso de GPU")
            seriesA: root.gpu1History
            maxValue: 100
            unit: "%"
            colourA: CortetsuDesign.colorTertiary
        }
    }
}
