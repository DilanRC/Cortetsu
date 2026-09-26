pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import QtCore
import Quickshell.Io

Item {
    id: root

    property var power: ({})
    property var batteryPowerHistory: []
    property var cpuPowerHistory: []
    property var amdPowerHistory: []
    property var nvidiaPowerHistory: []
    property string statusText: qsTr("Recopilando muestras de energía…")

    readonly property string helperPath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation) +
        "/.local/bin/cortetsu-hardware-power"

    readonly property var battery: power?.battery ?? ({})
    readonly property var cpu: power?.cpu ?? ({})
    readonly property var ac: power?.ac ?? ({})
    readonly property var gpus: power?.gpus ?? []

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function pushHistory(source, value): var {
        const next = Array.from(source ?? []);
        next.push(Math.max(0, Number(value ?? 0)));
        return next.slice(-90);
    }

    function gpuAt(index): var {
        return index >= 0 && index < gpus.length ? gpus[index] : ({});
    }

    function duration(minutes): string {
        if (minutes === null || minutes === undefined || isNaN(Number(minutes)))
            return "—";
        const total = Math.max(0, Math.round(Number(minutes)));
        const h = Math.floor(total / 60);
        const m = total % 60;
        return h > 0 ? `${h}h ${m}m` : `${m}m`;
    }

    function batteryEstimate(): string {
        const status = String(battery?.status ?? "").toLowerCase();
        if (status === "discharging" && battery?.remaining_minutes !== null && battery?.remaining_minutes !== undefined)
            return qsTr("Tiempo restante estimado: %1").arg(duration(battery.remaining_minutes));
        if (status === "charging" && battery?.time_to_full_minutes !== null && battery?.time_to_full_minutes !== undefined)
            return qsTr("Tiempo estimado para completar: %1").arg(duration(battery.time_to_full_minutes));
        if (status === "full")
            return qsTr("Batería completa");
        return qsTr("Estimación no disponible con el estado de energía actual");
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
                    root.statusText = qsTr("Telemetría de energía en vivo · intervalo de 2 s");
                } catch (error) {
                    root.statusText = qsTr("Telemetría de energía no disponible");
                    console.warn(`Hardware Center Energy: invalid JSON: ${error}`);
                }
            }
        }
    }

    Column {
        anchors.fill: parent
        spacing: 12

        Grid {
            id: summaryGrid
            width: parent.width
            height: 126
            columns: 3
            columnSpacing: 12

            Repeater {
                model: [
                    {
                        icon: root.ac?.online ? "power" : "battery_5_bar",
                        title: qsTr("Fuente de energía"),
                        value: root.ac?.online ? qsTr("Conectado a la corriente") : qsTr("Batería"),
                        detail: root.statusText
                    },
                    {
                        icon: "battery_charging_full",
                        title: qsTr("Energía de batería"),
                        value: root.battery?.present
                            ? `${root.number(root.battery?.energy_now_wh, 1)} / ${root.number(root.battery?.energy_full_wh, 1)} Wh`
                            : qsTr("No detectada"),
                        detail: root.batteryEstimate()
                    },
                    {
                        icon: "electric_bolt",
                        title: qsTr("Potencia actual"),
                        value: `${root.number(root.cpu?.package_power_w, 1)} W CPU · ${root.number(root.power?.total_gpu_power_w, 1)} W GPU`,
                        detail: root.battery?.present
                            ? `${root.number(root.battery?.power_w, 1)} W battery · ${root.number(root.battery?.health_percent, 1)}% health`
                            : qsTr("Telemetría de potencia de batería no disponible")
                    }
                ]

                delegate: Rectangle {
                    required property var modelData
                    width: (summaryGrid.width - 24) / 3
                    height: summaryGrid.height
                    radius: CortetsuDesign.radiusLarge
                    color: CortetsuDesign.colorSurface
                    border.width: 1
                    border.color: CortetsuDesign.colorOutlineVariant

                    Row {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        Rectangle {
                            width: 44
                            height: 44
                            anchors.verticalCenter: parent.verticalCenter
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSecondaryContainer

                            CortetsuIcon {
                                anchors.centerIn: parent
                                text: modelData.icon
                                color: CortetsuDesign.colorOnSecondaryContainer
                                iconSize: CortetsuTypography.iconLargePx
                            }
                        }

                        Column {
                            width: parent.width - 56
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2

                            CortetsuText {
                                width: parent.width
                                text: modelData.title
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                width: parent.width
                                text: modelData.value
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.titleSmallPx
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                width: parent.width
                                text: modelData.detail
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }

        Grid {
            width: parent.width
            height: parent.height - summaryGrid.height - 12
            columns: 2
            columnSpacing: 12
            rowSpacing: 12

            HistoryGraph {
                width: (parent.width - 12) / 2
                height: (parent.height - 12) / 2
                title: qsTr("Potencia de batería")
                icon: "battery_charging_full"
                headline: `${root.number(root.battery?.power_w, 2)} W`
                subtitle: root.batteryEstimate()
                legendA: qsTr("Flujo de batería")
                seriesA: root.batteryPowerHistory
                unit: "W"
                colourA: CortetsuDesign.colorPrimary
            }

            HistoryGraph {
                width: (parent.width - 12) / 2
                height: (parent.height - 12) / 2
                title: qsTr("Potencia del paquete de CPU")
                icon: "memory"
                headline: root.cpu?.package_power_w !== null && root.cpu?.package_power_w !== undefined
                    ? `${root.number(root.cpu.package_power_w, 2)} W`
                    : qsTr("No expuesta")
                subtitle: `${root.cpu?.driver ?? "—"} · ${root.cpu?.platform_profile ?? "—"}`
                legendA: qsTr("Paquete de CPU")
                seriesA: root.cpuPowerHistory
                unit: "W"
                colourA: CortetsuDesign.colorSecondary
            }

            HistoryGraph {
                width: (parent.width - 12) / 2
                height: (parent.height - 12) / 2
                title: qsTr("Potencia de GPU AMD")
                icon: "view_in_ar"
                headline: `${root.number(root.gpuAt(0)?.power_w, 2)} W`
                subtitle: `${root.gpuAt(0)?.runtime_status ?? "—"} · ${root.number(root.gpuAt(0)?.temp_c, 1)} °C`
                legendA: qsTr("GPU AMD")
                seriesA: root.amdPowerHistory
                unit: "W"
                colourA: CortetsuDesign.colorPrimary
            }

            HistoryGraph {
                width: (parent.width - 12) / 2
                height: (parent.height - 12) / 2
                title: qsTr("Potencia de GPU NVIDIA")
                icon: "sports_esports"
                headline: `${root.number(root.gpuAt(1)?.power_w, 2)} W`
                subtitle: `${root.gpuAt(1)?.pstate ?? "—"} · ${root.number(root.gpuAt(1)?.graphics_clock_mhz, 0)} MHz · ${root.number(root.gpuAt(1)?.temp_c, 1)} °C`
                legendA: qsTr("GPU NVIDIA")
                seriesA: root.nvidiaPowerHistory
                unit: "W"
                colourA: CortetsuDesign.colorTertiary
            }
        }
    }
}
