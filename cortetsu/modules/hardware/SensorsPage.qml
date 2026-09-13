pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var snapshot

    readonly property var cpu: snapshot?.cpu ?? ({})
    readonly property var gpus: snapshot?.gpus ?? []
    readonly property var fans: snapshot?.fans ?? []
    readonly property var battery: snapshot?.battery ?? ({})

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function gpuAt(index): var {
        return index >= 0 && index < gpus.length ? gpus[index] : ({});
    }

    Row {
        anchors.fill: parent
        spacing: 12

        Rectangle {
            id: coresCard
            width: parent.width * 0.56
            height: parent.height
            radius: CortetsuDesign.radiusLarge
            color: CortetsuDesign.colorSurface
            border.width: 1
            border.color: CortetsuDesign.colorOutlineVariant

            Column {
                anchors.fill: parent
                anchors.margins: 18
                spacing: 14

                Row {
                    width: parent.width

                    Column {
                        width: parent.width * 0.68
                        spacing: 2

                        CortetsuText {
                            text: qsTr("Núcleos de CPU")
                            color: CortetsuDesign.colorOnSurface
                            textSize: CortetsuTypography.titleMediumPx
                        }

                        CortetsuText {
                            width: parent.width
                            text: root.cpu?.model ?? "CPU"
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.labelSmallPx
                            elide: Text.ElideRight
                        }
                    }

                    Column {
                        width: parent.width * 0.32
                        spacing: 2

                        CortetsuText {
                            width: parent.width
                            text: `${root.number(root.cpu?.temp_c, 1)} °C`
                            color: CortetsuDesign.colorPrimary
                            textSize: CortetsuTypography.titleMediumPx
                            horizontalAlignment: Text.AlignRight
                        }

                        CortetsuText {
                            width: parent.width
                            text: `${root.number(root.cpu?.freq_mhz, 0)} MHz`
                            color: CortetsuDesign.colorOnSurfaceVariant
                            textSize: CortetsuTypography.labelSmallPx
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                }

                Grid {
                    id: coreGrid
                    width: parent.width
                    columns: 3
                    columnSpacing: 10
                    rowSpacing: 10

                    Repeater {
                        model: root.cpu?.per_core ?? []

                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            width: (coreGrid.width - coreGrid.columnSpacing * 2) / 3
                            height: 74
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSurfaceHigh

                            Column {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 7

                                Row {
                                    width: parent.width

                                    CortetsuText {
                                        width: parent.width * 0.55
                                        text: `CPU ${index}`
                                        color: CortetsuDesign.colorOnSurfaceVariant
                                        textSize: CortetsuTypography.labelSmallPx
                                    }

                                    CortetsuText {
                                        width: parent.width * 0.45
                                        text: `${Number(modelData ?? 0).toFixed(0)}%`
                                        color: CortetsuDesign.colorOnSurface
                                        textSize: CortetsuTypography.labelMediumPx
                                        horizontalAlignment: Text.AlignRight
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 8
                                    radius: 999
                                    color: CortetsuDesign.colorSurfaceHigh

                                    Rectangle {
                                        width: parent.width * Math.max(0, Math.min(1, Number(modelData ?? 0) / 100))
                                        height: parent.height
                                        radius: parent.radius
                                        color: CortetsuDesign.colorPrimary
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width - coresCard.width - 12
            height: parent.height
            spacing: 12

            Rectangle {
                width: parent.width
                height: (parent.height - 24) / 3
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 9

                    CortetsuText {
                        text: qsTr("Refrigeración")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleSmallPx
                    }

                    Repeater {
                        model: root.fans

                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            height: 23

                            CortetsuText {
                                width: parent.width * 0.66
                                text: modelData?.name ?? qsTr("Fan")
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                width: parent.width * 0.34
                                text: `${modelData?.rpm ?? "—"} RPM`
                                color: CortetsuDesign.colorPrimary
                                textSize: CortetsuTypography.labelMediumPx
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }

                    CortetsuText {
                        visible: root.fans.length === 0
                        text: qsTr("hwmon no expone datos de ventiladores")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.bodySmallPx
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: (parent.height - 24) / 3
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 7

                    CortetsuText {
                        text: qsTr("Thermals & power")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleSmallPx
                    }

                    Repeater {
                        model: [
                            { label: qsTr("CPU"), value: `${root.number(root.cpu?.temp_c, 1)} °C` },
                            { label: root.gpuAt(0)?.vendor ?? qsTr("GPU 1"), value: `${root.number(root.gpuAt(0)?.temp_c, 1)} °C · ${root.number(root.gpuAt(0)?.power_w, 1)} W` },
                            { label: root.gpuAt(1)?.vendor ?? qsTr("GPU 2"), value: `${root.number(root.gpuAt(1)?.temp_c, 1)} °C · ${root.number(root.gpuAt(1)?.power_w, 1)} W` }
                        ]

                        delegate: Row {
                            required property var modelData
                            width: parent.width
                            height: 24

                            CortetsuText {
                                width: parent.width * 0.38
                                text: modelData.label
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                            }

                            CortetsuText {
                                width: parent.width * 0.62
                                text: modelData.value
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.labelMediumPx
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: (parent.height - 24) / 3
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 8

                    CortetsuText {
                        text: qsTr("Batería")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleSmallPx
                    }

                    CortetsuText {
                        text: root.battery?.present
                            ? `${root.number(root.battery?.percent, 0)}% · ${root.battery?.status ?? "—"}`
                            : qsTr("No se detectó batería")
                        color: CortetsuDesign.colorPrimary
                        textSize: CortetsuTypography.titleMediumPx
                    }

                    CortetsuText {
                        text: root.battery?.present
                            ? `${qsTr("Consumo actual")}: ${root.number(root.battery?.power_w, 1)} W`
                            : ""
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelMediumPx
                    }

                    CortetsuText {
                        text: root.battery?.present
                            ? qsTr("Los valores de batería y ventiladores provienen directamente de las interfaces power_supply y hwmon del kernel.")
                            : qsTr("Sensor data is read only while Hardware Center is open.")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.labelSmallPx
                        wrapMode: Text.WordWrap
                        width: parent.width
                    }
                }
            }
        }
    }
}
