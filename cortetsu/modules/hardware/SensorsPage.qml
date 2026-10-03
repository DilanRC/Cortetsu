pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
import "Health.js" as Health

// Heat and cooling: each temperature against its limit, the load per core
// that produces it, and the fans that remove it.
Item {
    id: root

    required property var snapshot

    readonly property var cpu: snapshot?.cpu ?? ({})
    readonly property var gpus: snapshot?.gpus ?? []
    readonly property var fans: snapshot?.fans ?? []
    readonly property var battery: snapshot?.battery ?? ({})
    readonly property var cores: cpu?.per_core ?? []
    readonly property var health: Health.evaluate(snapshot)

    function severityOf(id): string {
        for (const issue of root.health.issues) {
            if (issue.id === id)
                return issue.severity;
        }
        return "";
    }

    Row {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Column {
            id: left
            width: Math.round((parent.width - parent.spacing) * 0.6)
            spacing: CortetsuDesign.spacingStandard

            Panel {
                width: parent.width
                height: thermals.implicitHeight + padding * 2

                Column {
                    id: thermals
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    SummaryLabel {
                        icon: "device_thermostat"
                        text: qsTr("Temperaturas")
                    }

                    Thermal {
                        width: parent.width
                        name: qsTr("CPU")
                        detail: root.cpu?.model ?? ""
                        celsius: root.cpu?.temp_c
                        limits: Health.limits.cpuTempC
                        severity: root.severityOf("cpu-temp")
                    }

                    Repeater {
                        model: root.gpus.length

                        delegate: Thermal {
                            required property int index
                            readonly property var gpu: root.gpus[index] ?? ({})

                            width: thermals.width
                            name: gpu.vendor ? qsTr("GPU %1").arg(gpu.vendor) : qsTr("GPU")
                            detail: Format.watts(gpu.power_w)
                            celsius: gpu.temp_c
                            limits: Health.limits.gpuTempC
                            severity: root.severityOf(`gpu-temp-${index}`)
                        }
                    }
                }
            }

            Panel {
                width: parent.width
                height: coreColumn.implicitHeight + padding * 2

                Column {
                    id: coreColumn
                    width: parent.width
                    spacing: CortetsuDesign.spacingStandard

                    SummaryLabel {
                        icon: "memory"
                        text: qsTr("Carga por núcleo")
                        detail: Format.join([
                            Format.percent(root.cpu?.usage) ? qsTr("total %1").arg(Format.percent(root.cpu.usage)) : "",
                            Format.gigahertz(root.cpu?.freq_mhz)
                        ])
                    }

                    CortetsuText {
                        visible: root.cores.length === 0
                        text: qsTr("La lectura no incluye datos por núcleo")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    Grid {
                        id: coreGrid
                        width: parent.width
                        columns: 3
                        columnSpacing: CortetsuDesign.spacingSpacious
                        rowSpacing: CortetsuDesign.spacingCompact

                        Repeater {
                            // Index-based: one cell per core, updated in place.
                            model: root.cores.length

                            delegate: Item {
                                id: core
                                required property int index
                                readonly property var usage: root.cores[core.index]

                                width: (coreGrid.width - coreGrid.columnSpacing * 2) / 3
                                height: 24

                                CortetsuText {
                                    id: coreName
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 22
                                    text: core.index
                                    color: CortetsuDesign.colorOnSurfaceVariant
                                    textSize: CortetsuTypography.labelMediumPx
                                }

                                CortetsuProgressBar {
                                    anchors.left: coreName.right
                                    anchors.right: coreValue.left
                                    anchors.rightMargin: CortetsuDesign.spacingCompact
                                    anchors.verticalCenter: parent.verticalCenter
                                    value: Format.fraction(core.usage)
                                    barHeight: 6
                                }

                                CortetsuText {
                                    id: coreValue
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 42
                                    horizontalAlignment: Text.AlignRight
                                    text: Format.percent(core.usage)
                                    textSize: CortetsuTypography.labelMediumPx
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width - left.width - parent.spacing
            spacing: CortetsuDesign.spacingStandard

            Panel {
                width: parent.width
                height: fanColumn.implicitHeight + padding * 2

                Column {
                    id: fanColumn
                    width: parent.width
                    spacing: CortetsuDesign.spacingUnit

                    SummaryLabel {
                        icon: "mode_fan"
                        text: qsTr("Ventiladores")
                    }

                    Item { width: 1; height: CortetsuDesign.spacingUnit }

                    CortetsuText {
                        visible: root.fans.length === 0
                        width: parent.width
                        wrapMode: Text.WordWrap
                        text: qsTr("El kernel no expone ningún ventilador en este equipo.")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    Repeater {
                        model: root.fans.length

                        delegate: FactRow {
                            required property int index
                            readonly property var fan: root.fans[index] ?? ({})

                            width: fanColumn.width
                            label: fan.name ?? ""
                            value: Format.known(fan.rpm) ? qsTr("%1 RPM").arg(fan.rpm) : ""
                            emphasized: true
                        }
                    }
                }
            }

            Panel {
                width: parent.width
                height: batteryColumn.implicitHeight + padding * 2

                Column {
                    id: batteryColumn
                    width: parent.width
                    spacing: CortetsuDesign.spacingUnit

                    SummaryLabel {
                        icon: "battery_full"
                        text: qsTr("Batería")
                    }

                    Item { width: 1; height: CortetsuDesign.spacingUnit }

                    CortetsuText {
                        visible: !root.battery?.present
                        text: qsTr("Este equipo no tiene batería")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    FactRow {
                        visible: !!root.battery?.present
                        width: parent.width
                        label: qsTr("Carga")
                        value: Format.percent(root.battery?.percent)
                        emphasized: true
                    }

                    FactRow {
                        visible: !!root.battery?.present
                        width: parent.width
                        label: qsTr("Estado")
                        value: ({
                            "Charging": qsTr("Cargando"),
                            "Discharging": qsTr("En uso"),
                            "Full": qsTr("Cargada"),
                            "Not charging": qsTr("Conectada, sin cargar")
                        })[root.battery?.status] ?? ""
                    }

                    FactRow {
                        visible: !!root.battery?.present
                        width: parent.width
                        label: qsTr("Flujo")
                        value: Format.watts(root.battery?.power_w)
                    }
                }
            }
        }
    }

    // A temperature read against the limits that flag it on the summary.
    component Thermal: Item {
        id: thermal

        property string name: ""
        property string detail: ""
        property var celsius: null
        property var limits: [90, 97]
        property string severity: ""

        height: 44

        CortetsuText {
            id: thermalName
            anchors.left: parent.left
            anchors.top: parent.top
            text: thermal.name
            textSize: CortetsuTypography.bodyPx
            font.weight: Font.DemiBold
        }

        CortetsuText {
            anchors.left: thermalName.right
            anchors.leftMargin: CortetsuDesign.spacingCompact
            anchors.right: reading.left
            anchors.rightMargin: CortetsuDesign.spacingStandard
            anchors.baseline: thermalName.baseline
            text: thermal.detail
            color: CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelMediumPx
            elide: Text.ElideRight
        }

        SummaryFacts {
            id: reading
            anchors.right: parent.right
            anchors.baseline: thermalName.baseline
            lead: Format.celsius(thermal.celsius) || qsTr("Sin sensor")
            rest: Format.known(thermal.celsius) ? qsTr("aviso a %1 °C").arg(thermal.limits[0]) : ""
            severity: thermal.severity
            textSize: CortetsuTypography.bodyPx
        }

        CortetsuProgressBar {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            // The track ends at the critical limit, so the fill shows how much
            // margin is left.
            value: Format.known(thermal.celsius) ? Math.min(1, Number(thermal.celsius) / thermal.limits[1]) : -1
            fillColor: thermal.severity === "critical"
                ? CortetsuDesign.colorVermillion
                : thermal.severity === "warning" ? CortetsuDesign.colorWarning : CortetsuDesign.colorPrimary
            barHeight: 6
        }
    }
}
