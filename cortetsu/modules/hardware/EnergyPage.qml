pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
import QtCore
import Quickshell.Io

Item {
    id: root

    property var power: ({})
    property var batteryPowerHistory: []
    property var cpuPowerHistory: []
    property var amdPowerHistory: []
    property var nvidiaPowerHistory: []
    readonly property int historyLength: 90
    property string statusText: qsTr("Recopilando muestras de energía…")

    readonly property string helperPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-hardware-power"

    readonly property var battery: power?.battery ?? ({})
    readonly property var cpu: power?.cpu ?? ({})
    readonly property var ac: power?.ac ?? ({})
    readonly property var gpus: power?.gpus ?? []

    function pushHistory(source, value): var {
        const next = Array.from(source ?? []);
        next.push(Math.max(0, Number(value ?? 0)));
        return next.slice(-root.historyLength);
    }

    function batteryEstimate(): string {
        const status = String(battery?.status ?? "").toLowerCase();
        if (status === "discharging" && Format.known(battery?.remaining_minutes))
            return qsTr("quedan unos %1").arg(Format.duration(Number(battery.remaining_minutes) * 60));
        if (status === "charging" && Format.known(battery?.time_to_full_minutes))
            return qsTr("completa en unos %1").arg(Format.duration(Number(battery.time_to_full_minutes) * 60));
        if (status === "full")
            return qsTr("carga completa");
        return "";
    }

    function refresh(): void {
        if (!probe.running)
            probe.running = true;
    }

    Component.onCompleted: { if (root.visible) refresh(); }
    onVisibleChanged: { if (visible) refresh(); }

    Timer {
        interval: 2000
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    // startup inventory: cortetsu:hardware-energy-probe
    Process {
        id: probe
        command: [root.helperPath]

        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.power = parsed;
                    root.batteryPowerHistory = root.pushHistory(root.batteryPowerHistory, parsed?.battery?.power_w);
                    root.cpuPowerHistory = root.pushHistory(root.cpuPowerHistory, parsed?.cpu?.package_power_w);
                    root.amdPowerHistory = root.pushHistory(root.amdPowerHistory, parsed?.gpus?.[0]?.power_w);
                    root.nvidiaPowerHistory = root.pushHistory(root.nvidiaPowerHistory, parsed?.gpus?.[1]?.power_w);
                    root.statusText = "";
                } catch (error) {
                    root.statusText = qsTr("La sonda de energía no devolvió datos válidos");
                    console.warn(`Hardware Center Energy: invalid JSON: ${error}`);
                }
            }
        }
    }

    readonly property var gpuHistories: [root.amdPowerHistory, root.nvidiaPowerHistory]
    readonly property bool hasCpuPower: Format.known(root.cpu?.package_power_w)
    readonly property real cellWidth: (width - CortetsuDesign.spacingStandard) / 2

    Column {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Panel {
            id: now
            width: parent.width
            height: 96

            Row {
                id: figures
                anchors.fill: parent
                spacing: CortetsuDesign.spacingSpacious

                readonly property real cell: (width - spacing * 2) / 3

                Figure {
                    width: figures.cell
                    icon: root.ac?.online ? "power" : "battery_full"
                    label: qsTr("Fuente")
                    value: root.power?.ac === undefined
                        ? ""
                        : root.ac?.online ? qsTr("Corriente") : qsTr("Batería")
                    detail: root.statusText
                }

                Figure {
                    width: figures.cell
                    icon: "battery_full"
                    label: qsTr("Energía en la batería")
                    value: root.power?.battery === undefined
                        ? ""
                        : !root.battery?.present
                            ? qsTr("Sin batería")
                            : `${Format.fixed(root.battery.energy_now_wh, 1)} / ${Format.withUnit(root.battery.energy_full_wh, 1, "Wh")}`
                    detail: Format.join([
                        root.batteryEstimate(),
                        Format.percent(root.battery?.health_percent) ? qsTr("salud %1").arg(Format.percent(root.battery.health_percent)) : ""
                    ])
                }

                Figure {
                    width: figures.cell
                    icon: "electric_bolt"
                    label: qsTr("Consumo de las GPU")
                    value: Format.watts(root.power?.total_gpu_power_w)
                    detail: root.hasCpuPower
                        ? qsTr("procesador %1").arg(Format.watts(root.cpu.package_power_w))
                        : qsTr("el procesador no expone su consumo")
                }
            }
        }

        Grid {
            id: graphs
            width: parent.width
            height: parent.height - now.height - parent.spacing
            columns: 2
            columnSpacing: CortetsuDesign.spacingStandard
            rowSpacing: CortetsuDesign.spacingStandard

            readonly property real cellHeight: (height - rowSpacing) / 2

            HistoryGraph {
                width: root.cellWidth
                height: graphs.cellHeight
                capacity: root.historyLength
                title: qsTr("Batería")
                icon: "battery_full"
                available: !!root.battery?.present
                unavailableText: qsTr("Este equipo no tiene batería")
                headline: Format.watts(root.battery?.power_w)
                subtitle: root.batteryEstimate()
                legendA: qsTr("Flujo")
                seriesA: root.batteryPowerHistory
                unit: "W"
            }

            HistoryGraph {
                width: root.cellWidth
                height: graphs.cellHeight
                capacity: root.historyLength
                title: qsTr("Procesador")
                icon: "memory"
                available: root.hasCpuPower
                unavailableText: qsTr("Este procesador no expone su consumo al sistema")
                headline: Format.watts(root.cpu?.package_power_w)
                subtitle: Format.join([root.cpu?.driver ?? "", root.cpu?.platform_profile ?? ""])
                legendA: qsTr("Paquete")
                seriesA: root.cpuPowerHistory
                unit: "W"
            }

            Repeater {
                // Always two cells so the grid keeps its shape; a missing GPU says so.
                model: 2

                delegate: HistoryGraph {
                    id: gpuGraph
                    required property int index
                    readonly property var gpu: root.gpus[gpuGraph.index] ?? null

                    width: root.cellWidth
                    height: graphs.cellHeight
                    capacity: root.historyLength
                    title: gpuGraph.gpu?.vendor ? qsTr("GPU %1").arg(gpuGraph.gpu.vendor) : qsTr("GPU %1").arg(gpuGraph.index + 1)
                    icon: "view_in_ar"
                    available: gpuGraph.gpu !== null && Format.known(gpuGraph.gpu.power_w)
                    unavailableText: gpuGraph.gpu === null ? qsTr("No hay una segunda GPU") : qsTr("Esta GPU no expone su consumo")
                    headline: Format.watts(gpuGraph.gpu?.power_w)
                    subtitle: Format.join([
                        Format.celsius(gpuGraph.gpu?.temp_c),
                        gpuGraph.gpu?.pstate ?? gpuGraph.gpu?.runtime_status ?? "",
                        Format.withUnit(gpuGraph.gpu?.graphics_clock_mhz, 0, "MHz")
                    ])
                    legendA: qsTr("Consumo")
                    seriesA: root.gpuHistories[gpuGraph.index]
                    unit: "W"
                }
            }
        }
    }

    // One current figure with what qualifies it.
    component Figure: Item {
        id: figure

        property string icon: ""
        property string label: ""
        property string value: ""
        property string detail: ""

        height: parent.height

        CortetsuIcon {
            id: figureIcon
            anchors.left: parent.left
            anchors.top: parent.top
            text: figure.icon
            color: CortetsuDesign.colorOnSurfaceMuted
            iconSize: CortetsuTypography.iconSmallPx
        }

        CortetsuText {
            anchors.left: figureIcon.right
            anchors.leftMargin: CortetsuDesign.spacingCompact
            anchors.right: parent.right
            anchors.verticalCenter: figureIcon.verticalCenter
            text: figure.label
            color: CortetsuDesign.colorOnSurfaceMuted
            textSize: CortetsuTypography.labelLargePx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: 4
            text: figure.value || qsTr("Leyendo…")
            textSize: CortetsuTypography.titleMediumPx
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        CortetsuText {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            text: figure.detail
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }
    }
}
