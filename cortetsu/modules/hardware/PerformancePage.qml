pragma ComponentBehavior: Bound

import QtQuick
import "../../theme"
import "Format.js" as Format

// Recent history of what moves: processor, memory, network, disk and each GPU.
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
    property int historyLength: 80

    property int selectedCpuCore: -1
    property bool showSwapHistory: false

    readonly property var cpu: snapshot?.cpu ?? ({})
    readonly property var memory: snapshot?.memory ?? ({})
    readonly property var network: snapshot?.network ?? ({})
    readonly property var diskIo: snapshot?.disk_io ?? ({})
    readonly property var gpus: snapshot?.gpus ?? []
    readonly property var gpuHistories: [root.gpu0History, root.gpu1History]
    readonly property var selectedCpuHistory: selectedCpuCore < 0
        ? cpuHistory
        : (selectedCpuCore < cpuCoreHistories.length ? cpuCoreHistories[selectedCpuCore] : [])
    readonly property var selectedCpuNow: selectedCpuCore < 0
        ? cpu?.usage
        : cpu?.per_core?.[selectedCpuCore]

    readonly property real cellWidth: (width - CortetsuDesign.spacingStandard) / 2
    readonly property real cellHeight: (height - CortetsuDesign.spacingStandard * 2) / 3

    function cycleCpu(): void {
        const count = Number(cpu?.cores ?? 0);
        selectedCpuCore = count <= 0 || selectedCpuCore >= count - 1 ? -1 : selectedCpuCore + 1;
    }

    Grid {
        anchors.fill: parent
        columns: 2
        columnSpacing: CortetsuDesign.spacingStandard
        rowSpacing: CortetsuDesign.spacingStandard

        HistoryGraph {
            width: root.cellWidth
            height: root.cellHeight
            capacity: root.historyLength
            title: root.selectedCpuCore < 0 ? qsTr("CPU") : qsTr("CPU, núcleo %1").arg(root.selectedCpuCore)
            icon: "memory"
            headline: Format.percent(root.selectedCpuNow)
            subtitle: Format.join([
                Format.celsius(root.cpu?.temp_c),
                Format.gigahertz(root.cpu?.freq_mhz),
                root.cpu?.governor ?? ""
            ])
            legendA: root.selectedCpuCore < 0 ? qsTr("Todos los núcleos") : qsTr("Núcleo %1").arg(root.selectedCpuCore)
            seriesA: root.selectedCpuHistory
            maxValue: 100
            unit: "%"
            actionLabel: root.selectedCpuCore < 0 ? qsTr("Total") : qsTr("Núcleo %1").arg(root.selectedCpuCore)
            onActionRequested: root.cycleCpu()
        }

        HistoryGraph {
            width: root.cellWidth
            height: root.cellHeight
            capacity: root.historyLength
            title: qsTr("Memoria")
            icon: "developer_board"
            headline: Format.ratioGib(root.memory?.used_gb, root.memory?.total_gb)
            subtitle: Format.join([
                Format.gib(root.memory?.available_gb) ? qsTr("%1 disponibles").arg(Format.gib(root.memory.available_gb)) : "",
                Format.gib(root.memory?.cache_gb) ? qsTr("caché %1").arg(Format.gib(root.memory.cache_gb)) : "",
                Format.gib(root.memory?.swap_used_gb) ? qsTr("swap %1").arg(Format.gib(root.memory.swap_used_gb)) : ""
            ])
            legendA: qsTr("En uso")
            legendB: root.showSwapHistory ? qsTr("Swap") : qsTr("Caché")
            seriesA: root.memoryUsedHistory
            seriesB: root.showSwapHistory ? root.swapUsedHistory : root.memoryCacheHistory
            maxValue: Math.max(1, Number(root.memory?.total_gb ?? 1))
            unit: "GiB"
            actionLabel: root.showSwapHistory ? qsTr("Swap") : qsTr("Caché")
            onActionRequested: root.showSwapHistory = !root.showSwapHistory
        }

        HistoryGraph {
            width: root.cellWidth
            height: root.cellHeight
            capacity: root.historyLength
            title: qsTr("Red")
            icon: "lan"
            available: !!root.network?.interface
            unavailableText: qsTr("Sin conexión de red activa")
            headline: root.network?.interface
                ? qsTr("baja %1 · sube %2 Mb/s").arg(Format.fixed(root.network.rx_mbps, 1)).arg(Format.fixed(root.network.tx_mbps, 1))
                : ""
            subtitle: Format.join([
                root.network?.ssid || (root.network?.interface ?? ""),
                Format.gib(root.network?.rx_total_gb) ? qsTr("recibidos %1").arg(Format.gib(root.network.rx_total_gb)) : "",
                Format.gib(root.network?.tx_total_gb) ? qsTr("enviados %1").arg(Format.gib(root.network.tx_total_gb)) : ""
            ])
            legendA: qsTr("Bajada")
            legendB: qsTr("Subida")
            seriesA: root.networkRxHistory
            seriesB: root.networkTxHistory
            unit: "Mb/s"
        }

        HistoryGraph {
            width: root.cellWidth
            height: root.cellHeight
            capacity: root.historyLength
            title: qsTr("Disco")
            icon: "hard_drive"
            headline: qsTr("lee %1 · escribe %2 MiB/s")
                .arg(Format.fixed(root.diskIo?.read_mib_s, 1) || "0.0")
                .arg(Format.fixed(root.diskIo?.write_mib_s, 1) || "0.0")
            subtitle: Format.join([
                root.diskIo?.device ?? "",
                Format.known(root.diskIo?.read_iops)
                    ? qsTr("%1 lecturas/s · %2 escrituras/s").arg(Format.fixed(root.diskIo.read_iops, 0)).arg(Format.fixed(root.diskIo.write_iops, 0))
                    : ""
            ])
            legendA: qsTr("Lectura")
            legendB: qsTr("Escritura")
            seriesA: root.diskReadHistory
            seriesB: root.diskWriteHistory
            unit: "MiB/s"
        }

        Repeater {
            // Always two cells so the grid keeps its shape; a missing GPU says so.
            model: 2

            delegate: HistoryGraph {
                id: gpuGraph
                required property int index
                readonly property var gpu: root.gpus[gpuGraph.index] ?? null

                width: root.cellWidth
                height: root.cellHeight
                capacity: root.historyLength
                title: gpuGraph.gpu?.vendor ? qsTr("GPU %1").arg(gpuGraph.gpu.vendor) : qsTr("GPU %1").arg(gpuGraph.index + 1)
                icon: "view_in_ar"
                available: gpuGraph.gpu !== null
                unavailableText: qsTr("No hay una segunda GPU")
                headline: Format.percent(gpuGraph.gpu?.usage)
                subtitle: Format.join([
                    Format.celsius(gpuGraph.gpu?.temp_c),
                    Format.watts(gpuGraph.gpu?.power_w),
                    Format.ratioGib(gpuGraph.gpu?.vram_used_gb, gpuGraph.gpu?.vram_total_gb)
                        ? qsTr("VRAM %1").arg(Format.ratioGib(gpuGraph.gpu.vram_used_gb, gpuGraph.gpu.vram_total_gb))
                        : ""
                ])
                legendA: qsTr("Uso")
                seriesA: root.gpuHistories[gpuGraph.index]
                maxValue: 100
                unit: "%"
            }
        }
    }
}
