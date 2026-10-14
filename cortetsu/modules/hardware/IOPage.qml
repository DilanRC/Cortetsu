pragma ComponentBehavior: Bound

import QtQuick
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format

// Storage and network: how full the root disk is, what each device is moving
// now, and the link this machine is on.
Item {
    id: root

    required property var snapshot

    readonly property var disk: snapshot?.disk ?? ({})
    readonly property var diskIo: snapshot?.disk_io ?? ({})
    readonly property var network: snapshot?.network ?? ({})
    readonly property var disks: snapshot?.disks_io ?? []
    readonly property bool online: !!network?.interface

    function rate(value, unit): string {
        return Format.withUnit(value, 1, unit);
    }

    Row {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        Column {
            id: storage
            width: Math.round((parent.width - parent.spacing) * 0.56)
            spacing: CortetsuDesign.spacingStandard

            Panel {
                width: parent.width
                height: rootDisk.implicitHeight + padding * 2

                Column {
                    id: rootDisk
                    width: parent.width
                    spacing: CortetsuDesign.spacingUnit

                    SummaryLabel {
                        icon: "hard_drive"
                        text: qsTr("Disco raíz")
                        detail: Format.join([root.diskIo?.device ?? "", root.diskIo?.model ?? ""])
                    }

                    Item {
                        width: parent.width
                        height: 40

                        CortetsuText {
                            id: usage
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            text: Format.percent(root.disk?.usage) || qsTr("Sin lectura")
                            textSize: CortetsuTypography.displaySmallPx
                            font.weight: Font.DemiBold
                        }

                        CortetsuText {
                            anchors.left: usage.right
                            anchors.leftMargin: CortetsuDesign.spacingStandard
                            anchors.baseline: usage.baseline
                            text: Format.ratioGib(root.disk?.used_gb, root.disk?.total_gb, 0)
                            color: CortetsuDesign.colorOnSurfaceMuted
                            textSize: CortetsuTypography.bodyLargePx
                        }
                    }

                    CortetsuProgressBar {
                        width: parent.width
                        value: Format.fraction(root.disk?.usage)
                        barHeight: 6
                    }

                    Item { width: 1; height: CortetsuDesign.spacingCompact }

                    Grid {
                        width: parent.width
                        columns: 2
                        columnSpacing: CortetsuDesign.spacingSpacious

                        readonly property real cell: (width - columnSpacing) / 2

                        FactRow { width: parent.cell; label: qsTr("Libre"); value: Format.gib(root.disk?.free_gb, 0); emphasized: true }
                        FactRow { width: parent.cell; label: qsTr("En uso"); value: Format.gib(root.disk?.used_gb, 0) }
                        FactRow { width: parent.cell; label: qsTr("Lectura"); value: root.rate(root.diskIo?.read_mib_s, "MiB/s") }
                        FactRow { width: parent.cell; label: qsTr("Escritura"); value: root.rate(root.diskIo?.write_mib_s, "MiB/s") }
                        FactRow { width: parent.cell; label: qsTr("Lecturas por segundo"); value: Format.fixed(root.diskIo?.read_iops, 0) }
                        FactRow { width: parent.cell; label: qsTr("Escrituras por segundo"); value: Format.fixed(root.diskIo?.write_iops, 0) }
                        FactRow { width: parent.cell; label: qsTr("Leído desde el arranque"); value: Format.withUnit(root.diskIo?.read_total_gb, 1, "GB") }
                        FactRow { width: parent.cell; label: qsTr("Escrito desde el arranque"); value: Format.withUnit(root.diskIo?.write_total_gb, 1, "GB") }
                    }
                }
            }

            Panel {
                width: parent.width
                height: devices.implicitHeight + padding * 2

                Column {
                    id: devices
                    width: parent.width
                    spacing: CortetsuDesign.spacingUnit

                    SummaryLabel {
                        icon: "storage"
                        text: qsTr("Dispositivos")
                        detail: root.disks.length > 0 ? qsTr("%1 detectados").arg(root.disks.length) : ""
                    }

                    Item { width: 1; height: CortetsuDesign.spacingUnit }

                    CortetsuText {
                        visible: root.disks.length === 0
                        text: qsTr("No se detectó ningún dispositivo de bloque")
                        color: CortetsuDesign.colorOnSurfaceVariant
                        textSize: CortetsuTypography.bodySmallPx
                    }

                    Repeater {
                        model: root.disks.length

                        delegate: Item {
                            id: device
                            required property int index
                            readonly property var entry: root.disks[device.index] ?? ({})

                            width: devices.width
                            height: 40

                            CortetsuText {
                                id: deviceName
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 84
                                text: device.entry.device ?? ""
                                textSize: CortetsuTypography.bodyPx
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                anchors.left: deviceName.right
                                anchors.right: deviceRates.left
                                anchors.rightMargin: CortetsuDesign.spacingStandard
                                anchors.verticalCenter: parent.verticalCenter
                                text: Format.join([
                                    device.entry.model ?? "",
                                    device.entry.rotational ? qsTr("disco giratorio") : ""
                                ])
                                color: CortetsuDesign.colorOnSurfaceVariant
                                textSize: CortetsuTypography.bodySmallPx
                                elide: Text.ElideRight
                            }

                            CortetsuText {
                                id: deviceRates
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: qsTr("lee %1 · escribe %2 MiB/s")
                                    .arg(Format.fixed(device.entry.read_mib_s, 1) || "0.0")
                                    .arg(Format.fixed(device.entry.write_mib_s, 1) || "0.0")
                                color: CortetsuDesign.colorOnSurfaceMuted
                                textSize: CortetsuTypography.bodySmallPx
                            }
                        }
                    }
                }
            }
        }

        Panel {
            width: parent.width - storage.width - parent.spacing
            height: link.implicitHeight + padding * 2

            Column {
                id: link
                width: parent.width
                spacing: CortetsuDesign.spacingUnit

                SummaryLabel {
                    icon: root.online ? "lan" : "signal_disconnected"
                    text: qsTr("Red")
                    detail: root.network?.interface ?? ""
                }

                Item {
                    width: parent.width
                    height: 40

                    CortetsuText {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        text: root.online ? (root.network.ssid || root.network.interface) : qsTr("Sin conexión")
                        textSize: CortetsuTypography.titleLargePx
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                Item { width: 1; height: CortetsuDesign.spacingCompact }

                CortetsuText {
                    visible: !root.online
                    width: parent.width
                    wrapMode: Text.WordWrap
                    text: qsTr("Ninguna interfaz tiene ruta de salida. Las conexiones se gestionan desde el indicador de red de la barra.")
                    color: CortetsuDesign.colorOnSurfaceVariant
                    textSize: CortetsuTypography.bodySmallPx
                }

                Column {
                    visible: root.online
                    width: parent.width

                    FactRow { width: parent.width; label: qsTr("Bajada"); value: root.rate(root.network?.rx_mbps, "Mb/s"); emphasized: true }
                    FactRow { width: parent.width; label: qsTr("Subida"); value: root.rate(root.network?.tx_mbps, "Mb/s"); emphasized: true }
                    FactRow { width: parent.width; label: qsTr("Recibido desde el arranque"); value: Format.withUnit(root.network?.rx_total_gb, 2, "GB") }
                    FactRow { width: parent.width; label: qsTr("Enviado desde el arranque"); value: Format.withUnit(root.network?.tx_total_gb, 2, "GB") }
                    FactRow { visible: !!root.network?.ssid; width: parent.width; label: qsTr("Señal"); value: Format.withUnit(root.network?.signal_dbm, 0, "dBm") }
                    FactRow { visible: !!root.network?.ssid; width: parent.width; label: qsTr("Velocidad de enlace"); value: Format.withUnit(root.network?.bitrate_mbps, 0, "Mb/s") }
                    FactRow { width: parent.width; label: qsTr("IPv4"); value: root.network?.ipv4 ?? "" }
                    FactRow { width: parent.width; label: qsTr("MAC"); value: root.network?.mac ?? "" }
                }
            }
        }
    }
}
