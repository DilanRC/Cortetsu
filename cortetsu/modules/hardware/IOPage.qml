pragma ComponentBehavior: Bound

import QtQuick
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var snapshot

    readonly property var disk: snapshot?.disk ?? ({})
    readonly property var diskIo: snapshot?.disk_io ?? ({})
    readonly property var network: snapshot?.network ?? ({})
    readonly property var disks: snapshot?.disks_io ?? []

    function number(value, digits = 1): string {
        if (value === null || value === undefined || isNaN(Number(value)))
            return "—";
        return Number(value).toFixed(digits);
    }

    function gib(value): string {
        return value === null || value === undefined ? "—" : `${number(value, 2)} GiB`;
    }

    function row(label, value): var {
        return { label: label, value: value };
    }

    Row {
        anchors.fill: parent
        spacing: 12

        Column {
            width: parent.width * 0.55
            height: parent.height
            spacing: 12

            Rectangle {
                width: parent.width
                height: (parent.height - 12) * 0.54
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
                        spacing: 12

                        Rectangle {
                            width: 46
                            height: 46
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSecondaryContainer

                            CortetsuIcon {
                                anchors.centerIn: parent
                                text: "hard_drive"
                                color: CortetsuDesign.colorOnSecondaryContainer
                                iconSize: CortetsuTypography.iconLargePx
                            }
                        }

                        Column {
                            width: parent.width - 58
                            spacing: 2

                            Row {
                                width: parent.width

                                CortetsuText {
                                    width: parent.width * 0.58
                                    text: qsTr("Almacenamiento / raíz")
                                    color: CortetsuDesign.colorOnSurface
                                    textSize: CortetsuTypography.titleMediumPx
                                }

                                CortetsuText {
                                    width: parent.width * 0.42
                                    text: `${root.number(root.disk?.usage, 1)}%`
                                    color: CortetsuDesign.colorPrimary
                                    textSize: CortetsuTypography.titleMediumPx
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            CortetsuText {
                                width: parent.width
                                text: `${root.diskIo?.model ?? root.diskIo?.device ?? "root"}`
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 10
                        radius: 999
                        color: CortetsuDesign.colorSurfaceHigh

                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, Number(root.disk?.usage ?? 0) / 100))
                            height: parent.height
                            radius: parent.radius
                            color: CortetsuDesign.colorPrimary
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 11

                        Repeater {
                            model: [
                                root.row(qsTr("Usado"), root.gib(root.disk?.used_gb)),
                                root.row(qsTr("Libre"), root.gib(root.disk?.free_gb)),
                                root.row(qsTr("Lectura"), `${root.number(root.diskIo?.read_mib_s, 2)} MiB/s`),
                                root.row(qsTr("Escritura"), `${root.number(root.diskIo?.write_mib_s, 2)} MiB/s`),
                                root.row(qsTr("IOPS de lectura"), root.number(root.diskIo?.read_iops, 0)),
                                root.row(qsTr("IOPS de escritura"), root.number(root.diskIo?.write_iops, 0)),
                                root.row(qsTr("Lectura total"), root.gib(root.diskIo?.read_total_gb)),
                                root.row(qsTr("Escritura total"), root.gib(root.diskIo?.write_total_gb))
                            ]

                            delegate: Row {
                                required property var modelData
                                width: (parent.width - 20) / 2
                                height: 22

                                CortetsuText {
                                    width: parent.width * 0.5
                                    text: modelData.label
                                    color: CortetsuDesign.colorOutline
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                                CortetsuText {
                                    width: parent.width * 0.5
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
            }

            Rectangle {
                width: parent.width
                height: parent.height - parent.children[0].height - 12
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    Row {
                        width: parent.width

                        CortetsuText {
                            width: parent.width * 0.6
                            text: qsTr("Dispositivos de bloque detectados")
                            color: CortetsuDesign.colorOnSurface
                            textSize: CortetsuTypography.titleSmallPx
                        }

                        CortetsuText {
                            width: parent.width * 0.4
                        text: `${root.disks.length} ${qsTr("dispositivos")}`
                            color: CortetsuDesign.colorOutline
                            textSize: CortetsuTypography.labelSmallPx
                            horizontalAlignment: Text.AlignRight
                        }
                    }

                    Repeater {
                        model: root.disks.length ? root.disks : [root.diskIo]

                        delegate: Rectangle {
                            required property var modelData
                            width: parent.width
                            height: 52
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSurfaceHigh

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.54
                                    spacing: 1

                                    CortetsuText {
                                        text: modelData?.device ?? qsTr("raíz")
                                        color: CortetsuDesign.colorOnSurface
                                        textSize: CortetsuTypography.labelMediumPx
                                    }
                                    CortetsuText {
                                        width: parent.width
                                        text: modelData?.model ?? modelData?.serial ?? ""
                                        color: CortetsuDesign.colorOutline
                                        textSize: CortetsuTypography.labelSmallPx
                                        elide: Text.ElideRight
                                    }
                                }

                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.23
                                    text: `${root.number(modelData?.read_mib_s, 2)} R`
                                    color: CortetsuDesign.colorPrimary
                                    textSize: CortetsuTypography.labelMediumPx
                                    horizontalAlignment: Text.AlignRight
                                }

                                CortetsuText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width * 0.23
                                    text: `${root.number(modelData?.write_mib_s, 2)} W`
                                    color: CortetsuDesign.colorTertiary
                                    textSize: CortetsuTypography.labelMediumPx
                                    horizontalAlignment: Text.AlignRight
                                }
                            }
                        }
                    }
                }
            }
        }

        Column {
            width: parent.width - parent.children[0].width - 12
            height: parent.height
            spacing: 12

            Rectangle {
                width: parent.width
                height: (parent.height - 12) * 0.58
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 13

                    Row {
                        width: parent.width
                        spacing: 12

                        Rectangle {
                            width: 46
                            height: 46
                            radius: CortetsuDesign.radiusMedium
                            color: CortetsuDesign.colorSecondaryContainer

                            CortetsuIcon {
                                anchors.centerIn: parent
                                text: "wifi"
                                color: CortetsuDesign.colorOnSecondaryContainer
                                iconSize: CortetsuTypography.iconLargePx
                            }
                        }

                        Column {
                            width: parent.width - 58
                            spacing: 2

                            CortetsuText {
                                text: root.network?.interface ?? qsTr("Sin interfaz activa")
                                color: CortetsuDesign.colorOnSurface
                                textSize: CortetsuTypography.titleMediumPx
                            }

                            CortetsuText {
                                width: parent.width
                                text: root.network?.ssid
                                    ? `${root.network.ssid} · ${root.network?.ipv4 ?? ""}`
                                    : (root.network?.ipv4 ?? qsTr("Ruta de red activa"))
                                color: CortetsuDesign.colorOutline
                                textSize: CortetsuTypography.labelSmallPx
                                elide: Text.ElideRight
                            }
                        }
                    }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: 20
                        rowSpacing: 12

                        Repeater {
                            model: [
                                root.row(qsTr("Descarga"), `${root.number(root.network?.rx_mbps, 2)} Mb/s`),
                                root.row(qsTr("Subida"), `${root.number(root.network?.tx_mbps, 2)} Mb/s`),
                                root.row(qsTr("RX total"), `${root.number(root.network?.rx_total_gb, 2)} GiB`),
                                root.row(qsTr("TX total"), `${root.number(root.network?.tx_total_gb, 2)} GiB`),
                                root.row(qsTr("Señal"), root.network?.signal_dbm !== undefined ? `${root.network.signal_dbm} dBm` : "—"),
                                root.row(qsTr("Enlace"), root.network?.bitrate_mbps !== undefined ? `${root.number(root.network.bitrate_mbps, 0)} Mb/s` : "—"),
                                root.row(qsTr("IPv4"), root.network?.ipv4 ?? "—"),
                                root.row(qsTr("MAC"), root.network?.mac ?? "—")
                            ]

                            delegate: Row {
                                required property var modelData
                                width: (parent.width - 20) / 2
                                height: 24

                                CortetsuText {
                                    width: parent.width * 0.46
                                    text: modelData.label
                                    color: CortetsuDesign.colorOutline
                                    textSize: CortetsuTypography.labelSmallPx
                                }
                                CortetsuText {
                                    width: parent.width * 0.54
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
            }

            Rectangle {
                width: parent.width
                height: parent.height - parent.children[0].height - 12
                radius: CortetsuDesign.radiusLarge
                color: CortetsuDesign.colorSurface
                border.width: 1
                border.color: CortetsuDesign.colorOutlineVariant

                Column {
                    anchors.fill: parent
                    anchors.margins: 18
                    spacing: 10

                    CortetsuText {
                        text: qsTr("Resumen de transferencia")
                        color: CortetsuDesign.colorOnSurface
                        textSize: CortetsuTypography.titleSmallPx
                    }

                    CortetsuText {
                        width: parent.width
                        text: qsTr("La página de E/S usa contadores del kernel y solo toma muestras mientras el Centro de hardware está abierto.")
                        color: CortetsuDesign.colorOutline
                        textSize: CortetsuTypography.bodySmallPx
                        wrapMode: Text.WordWrap
                    }

                    CortetsuText {
                        width: parent.width
                        text: `${qsTr("Disco")}: ${root.number(root.diskIo?.read_mib_s, 2)} L / ${root.number(root.diskIo?.write_mib_s, 2)} E MiB/s`
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelMediumPx
                    }

                    CortetsuText {
                        width: parent.width
                        text: `${qsTr("Red")}: ${root.number(root.network?.rx_mbps, 2)} ↓ / ${root.number(root.network?.tx_mbps, 2)} ↑ Mb/s`
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.labelMediumPx
                    }
                }
            }
        }
    }
}
