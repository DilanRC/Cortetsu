pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "summary"
import "Format.js" as Format
import "SystemInfo.js" as SystemInfo

// What this machine is: the firmware identity (DMI) beside the software and
// the parts the probe already reads. Fn+Esc opens the Hardware Center here,
// the key HP labels «información del sistema». Nothing here is sampled: the
// DMI files are read once and the rest comes from the shared reading.
Item {
    id: root

    required property var snapshot

    readonly property var gpus: root.snapshot?.gpus ?? []
    readonly property var cpu: root.snapshot?.cpu ?? ({})

    // A sysfs DMI attribute, read once. product_serial is root-only and is
    // not read at all.
    component DmiField: FileView {
        property string value: ""
        required property string attribute
        path: "/sys/class/dmi/id/" + attribute
        watchChanges: false
        printErrors: false
        onLoaded: value = SystemInfo.clean(text())
    }

    DmiField { id: vendor; attribute: "sys_vendor" }
    DmiField { id: product; attribute: "product_name" }
    DmiField { id: sku; attribute: "product_sku" }
    DmiField { id: board; attribute: "board_name" }
    DmiField { id: chassis; attribute: "chassis_type" }
    DmiField { id: biosVendor; attribute: "bios_vendor" }
    DmiField { id: biosVersion; attribute: "bios_version" }
    DmiField { id: biosDate; attribute: "bios_date" }

    FileView {
        id: osRelease
        property string name: ""
        path: "/etc/os-release"
        watchChanges: false
        printErrors: false
        onLoaded: {
            const match = /^PRETTY_NAME="?([^"\n]*)"?$/m.exec(text());
            name = match ? match[1].trim() : "";
        }
    }

    readonly property var machineRows: [
        { label: qsTr("Fabricante"), value: vendor.value },
        { label: qsTr("Modelo"), value: product.value },
        { label: qsTr("SKU"), value: sku.value },
        { label: qsTr("Placa base"), value: board.value },
        { label: qsTr("Tipo"), value: SystemInfo.chassis(chassis.value) },
        { label: qsTr("BIOS"), value: Format.join([biosVendor.value, biosVersion.value], " ") },
        { label: qsTr("Fecha del BIOS"), value: SystemInfo.biosDate(biosDate.value) }
    ]

    readonly property var softwareRows: [
        { label: qsTr("Sistema"), value: osRelease.name },
        { label: qsTr("Kernel"), value: root.snapshot?.kernel ?? "" },
        { label: qsTr("Nombre del equipo"), value: root.snapshot?.host ?? "" },
        { label: qsTr("Encendido"), value: Format.duration(root.snapshot?.uptime_sec) }
    ]

    readonly property var partRows: {
        const rows = [
            { label: qsTr("Procesador"), value: root.cpu?.model ?? "" },
            { label: qsTr("Hilos"), value: Number(root.cpu?.cores ?? 0) > 0 ? String(root.cpu.cores) : "" },
            { label: qsTr("Memoria"), value: Format.gib(root.snapshot?.memory?.total_gb, 1) }
        ];
        for (const gpu of root.gpus)
            rows.push({ label: qsTr("Gráficos"), value: Format.join([gpu?.name ?? "", Format.size(gpu?.vram_total_gb)]) });
        for (const screen of Quickshell.screens)
            rows.push({
                label: screen.name ? qsTr("Pantalla %1").arg(screen.name) : qsTr("Pantalla"),
                value: Format.join([`${screen.width} × ${screen.height}`, screen.model ?? ""])
            });
        return rows;
    }

    component Section: Panel {
        id: section
        required property string icon
        required property string title
        required property var rows
        height: body.implicitHeight + padding * 2

        Column {
            id: body
            width: parent.width
            spacing: CortetsuDesign.spacingUnit

            SummaryLabel {
                icon: section.icon
                text: section.title
            }

            Item { width: 1; height: CortetsuDesign.spacingUnit }

            Repeater {
                model: section.rows

                delegate: FactRow {
                    required property var modelData
                    width: body.width
                    label: modelData.label
                    value: modelData.value
                }
            }
        }
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        contentHeight: columns.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Row {
            id: columns
            width: scroller.width
            spacing: CortetsuDesign.spacingStandard

            Column {
                id: left
                width: Math.round((parent.width - parent.spacing) / 2)
                spacing: CortetsuDesign.spacingStandard

                Section {
                    width: parent.width
                    icon: "laptop_chromebook"
                    title: qsTr("Equipo")
                    rows: root.machineRows
                }

                CortetsuButton {
                    id: copyButton
                    objectName: "systemCopy"
                    property bool copied: false
                    icon: copied ? "check" : "content_copy"
                    label: copied ? qsTr("Copiado") : qsTr("Copiar información")
                    tooltipText: qsTr("Copia estos datos como texto, para soporte técnico")
                    onClicked: {
                        Quickshell.clipboardText = SystemInfo.report(
                            root.machineRows.concat(root.softwareRows, root.partRows));
                        copyButton.copied = true;
                        copiedReset.restart();
                    }
                }

                Timer {
                    id: copiedReset
                    interval: 2000
                    onTriggered: copyButton.copied = false
                }
            }

            Column {
                width: parent.width - left.width - parent.spacing
                spacing: CortetsuDesign.spacingStandard

                Section {
                    width: parent.width
                    icon: "terminal"
                    title: qsTr("Software")
                    rows: root.softwareRows
                }

                Section {
                    width: parent.width
                    icon: "memory"
                    title: qsTr("Componentes")
                    rows: root.partRows
                }
            }
        }
    }
}
