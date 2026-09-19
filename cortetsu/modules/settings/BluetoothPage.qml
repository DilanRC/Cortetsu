pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../components"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuSearchBar.qml"

// BlueZ is presented as a discoverable list plus an inspector. A device row
// only calls the BluetoothDevice API; no connection state is simulated here.
Item {
    id: root

    property string query: ""
    property bool connectedOnly: false
    property int selectedIndex: 0

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool adapterEnabled: root.adapter?.enabled ?? false
    readonly property bool discovering: root.adapter?.discovering ?? false
    readonly property var allDevices: [...Bluetooth.devices.values].sort((left, right) =>
        Number(right.connected) - Number(left.connected)
        || Number(right.paired) - Number(left.paired)
        || String(left.name ?? "").localeCompare(String(right.name ?? "")))
    readonly property var filteredDevices: {
        const needle = root.query.trim().toLowerCase();
        return root.allDevices.filter(device => {
            const name = String(device?.name ?? "").toLowerCase();
            const matchesQuery = !needle || name.includes(needle)
                || String(device?.address ?? "").toLowerCase().includes(needle);
            return matchesQuery && (!root.connectedOnly || device.connected);
        });
    }
    readonly property var selectedDevice: root.filteredDevices[root.selectedIndex] ?? null
    readonly property int connectedCount: root.allDevices.filter(device => device.connected).length
    readonly property bool compactLayout: width < 760

    onQueryChanged: if (root.selectedIndex >= root.filteredDevices.length) root.selectedIndex = 0
    onConnectedOnlyChanged: root.selectedIndex = 0

    implicitHeight: body.implicitHeight

    function deviceName(device): string {
        return device?.name ?? qsTr("Dispositivo Bluetooth");
    }

    function deviceStatus(device): string {
        if (!device)
            return qsTr("Sin dispositivo seleccionado");
        if (root.deviceBusy(device))
            return qsTr("Conectando…");
        if (device.connected)
            return device.batteryAvailable
                ? qsTr("Conectado · batería %1%").arg(Math.round(device.battery * 100))
                : qsTr("Conectado");
        return device.paired ? qsTr("Vinculado · disponible") : qsTr("Disponible");
    }

    function deviceIcon(device): string {
        return device?.connected ? "bluetooth_connected" : "bluetooth";
    }

    function deviceBusy(device): bool {
        return device?.state === BluetoothDeviceState.Connecting
            || device?.state === BluetoothDeviceState.Disconnecting;
    }

    function toggleSelected(): void {
        if (!root.selectedDevice)
            return;
        if (root.selectedDevice.connected)
            root.selectedDevice.disconnect();
        else
            root.selectedDevice.connect();
    }

    function forgetSelected(): void {
        if (root.selectedDevice?.paired && !root.selectedDevice.connected)
            root.selectedDevice.forget();
    }

    ColumnLayout {
        id: body
        width: parent.width
        spacing: CortetsuDesign.spacingStandard

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Bluetooth")
            detail: qsTr("Dispositivos, emparejamiento y estado de BlueZ en vivo")
        }

        CortetsuSurface {
            Layout.fillWidth: true
            implicitHeight: 116
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: root.adapterEnabled
                ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.58)
                : Qt.alpha(CortetsuDesign.colorWarning, 0.10)
            outlineColor: root.adapterEnabled
                ? Qt.alpha(CortetsuDesign.colorPrimary, 0.42)
                : Qt.alpha(CortetsuDesign.colorWarning, 0.42)
            outlined: true

            RowLayout {
                anchors.fill: parent
                anchors.margins: CortetsuDesign.spacingStandard
                spacing: CortetsuDesign.spacingStandard

                CortetsuSurface {
                    Layout.preferredWidth: 64
                    Layout.preferredHeight: 64
                    radiusValue: CortetsuDesign.radiusMedium
                    baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.20)
                    outlined: false
                    CortetsuIcon {
                        anchors.centerIn: parent
                        text: root.connectedCount > 0 ? "bluetooth_connected" : "bluetooth"
                        iconSize: CortetsuTypography.iconLargePx
                        color: root.adapterEnabled
                            ? CortetsuDesign.colorPrimary
                            : CortetsuDesign.colorWarning
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    CortetsuText {
                        Layout.fillWidth: true
                        text: root.adapterEnabled
                            ? qsTr("Bluetooth activado")
                            : qsTr("Bluetooth desactivado")
                        textSize: CortetsuTypography.titleMediumPx
                        font.weight: Font.DemiBold
                    }
                    CortetsuText {
                        Layout.fillWidth: true
                        text: qsTr("%1 conectados · %2 conocidos")
                            .arg(root.connectedCount)
                            .arg(root.allDevices.length)
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }

                ColumnLayout {
                    Layout.minimumWidth: 160
                    spacing: CortetsuDesign.spacingCompact
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: qsTr("Adaptador")
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuToggle {
                            checked: root.adapterEnabled
                            disabled: !root.adapter
                            onToggled: checked => { if (root.adapter) root.adapter.enabled = checked; }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: root.discovering ? qsTr("Buscando dispositivos") : qsTr("Búsqueda detenida")
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuToggle {
                            checked: root.discovering
                            disabled: !root.adapterEnabled
                            onToggled: checked => { if (root.adapter) root.adapter.discovering = checked; }
                        }
                    }
                }
            }
        }

        Flow {
            id: workbench
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingSection
            property bool compact: root.compactLayout
            readonly property real workbenchHeight: compact
                ? listPanel.height + detailPanel.height + spacing
                : Math.max(listPanel.height, detailPanel.height)
            Layout.preferredHeight: workbench.workbenchHeight
            height: workbench.workbenchHeight

            Item {
                id: listPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.min(390, Math.max(340, workbench.width * 0.36))
                height: workbench.compact ? 440 : 560

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.66)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingCompact
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact
                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "bluetooth"
                            label: qsTr("Todos")
                            active: !root.connectedOnly
                            onClicked: { root.connectedOnly = false; root.selectedIndex = 0; }
                        }
                        CortetsuButton {
                            Layout.fillWidth: true
                            compact: true
                            icon: "bluetooth_connected"
                            label: qsTr("Conectados")
                            active: root.connectedOnly
                            onClicked: { root.connectedOnly = true; root.selectedIndex = 0; }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuText {
                            Layout.fillWidth: true
                            text: qsTr("%1 dispositivos visibles").arg(root.filteredDevices.length)
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorOnSurfaceVariant
                        }
                        CortetsuText {
                            text: root.discovering ? qsTr("Escaneando") : qsTr("En reposo")
                            textSize: CortetsuTypography.labelSmallPx
                            color: root.discovering ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
                        }
                    }

                    CortetsuSearchBar {
                        Layout.fillWidth: true
                        compact: true
                        placeholderText: qsTr("Filtrar dispositivos…")
                        onTextChanged: root.query = text
                    }

                    ListView {
                        id: deviceList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 3
                        model: root.filteredDevices
                        currentIndex: root.selectedIndex
                        onCurrentIndexChanged: if (currentIndex >= 0) root.selectedIndex = currentIndex

                        delegate: CortetsuListRow {
                            id: deviceDelegate
                            required property BluetoothDevice modelData
                            required property int index
                            width: deviceList.width
                            icon: root.deviceIcon(deviceDelegate.modelData)
                            title: root.deviceName(deviceDelegate.modelData)
                            subtitle: root.deviceStatus(deviceDelegate.modelData)
                            disabled: root.deviceBusy(deviceDelegate.modelData)
                            selected: deviceDelegate.index === root.selectedIndex
                                || (root.selectedIndex < 0 && deviceDelegate.modelData?.connected)
                            onClicked: root.selectedIndex = deviceDelegate.index
                        }

                        CortetsuStateMessage {
                            anchors.centerIn: parent
                            visible: deviceList.count === 0
                            kind: root.adapterEnabled ? "empty" : "error"
                            icon: root.adapterEnabled ? "bluetooth" : "bluetooth_disabled"
                            title: root.adapterEnabled
                                ? (root.query.length > 0 ? qsTr("No hay coincidencias") : qsTr("No hay dispositivos conocidos"))
                                : qsTr("Bluetooth está apagado")
                            detail: root.adapterEnabled
                                ? qsTr("Activa la búsqueda o empareja un dispositivo para verlo aquí")
                                : qsTr("Activa el adaptador para gestionar dispositivos")
                        }
                    }
                }
            }

            Item {
                id: detailPanel
                width: workbench.compact
                    ? workbench.width
                    : Math.max(0, workbench.width - listPanel.width - workbench.spacing)
                height: workbench.compact ? 520 : 560

                CortetsuSurface {
                    anchors.fill: parent
                    baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlass, 0.56)
                    outlineColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.48)
                    outlined: true
                    radiusValue: CortetsuDesign.radiusMedium
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: CortetsuDesign.spacingStandard
                    spacing: CortetsuDesign.spacingStandard
                    visible: !!root.selectedDevice

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuSurface {
                            Layout.preferredWidth: 56
                            Layout.preferredHeight: 56
                            radiusValue: CortetsuDesign.radiusMedium
                            baseColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.16)
                            outlined: false
                            CortetsuIcon {
                                anchors.centerIn: parent
                                text: root.deviceIcon(root.selectedDevice)
                                iconSize: CortetsuTypography.iconLargePx
                                color: CortetsuDesign.colorPrimary
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.deviceName(root.selectedDevice)
                                textSize: CortetsuTypography.titleMediumPx
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            CortetsuText {
                                Layout.fillWidth: true
                                text: root.deviceStatus(root.selectedDevice)
                                textSize: CortetsuTypography.bodySmallPx
                                color: root.selectedDevice?.connected
                                    ? CortetsuDesign.colorSuccess
                                    : CortetsuDesign.colorOnSurfaceVariant
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuButton {
                            Layout.fillWidth: true
                            icon: root.selectedDevice?.connected ? "link_off" : "link"
                            label: root.selectedDevice?.connected ? qsTr("Desconectar") : qsTr("Conectar")
                            disabled: !root.adapterEnabled || root.deviceBusy(root.selectedDevice)
                            onClicked: root.toggleSelected()
                        }
                        CortetsuButton {
                            compact: true
                            icon: "delete_outline"
                            label: qsTr("Olvidar")
                            visible: root.selectedDevice?.paired ?? false
                            disabled: root.selectedDevice?.connected ?? true
                            onClicked: root.forgetSelected()
                        }
                    }

                    CortetsuSurface {
                        Layout.fillWidth: true
                        implicitHeight: root.selectedDevice?.batteryAvailable ? 150 : 104
                        radiusValue: CortetsuDesign.radiusMedium
                        baseColor: Qt.alpha(CortetsuDesign.colorSurfaceGlassStrong, 0.66)
                        outlined: true

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: CortetsuDesign.spacingStandard
                            spacing: CortetsuDesign.spacingCompact
                            DetailRow { label: qsTr("Conexión"); value: root.selectedDevice?.connected ? qsTr("Conectado") : qsTr("Desconectado") }
                            DetailRow { label: qsTr("Emparejamiento"); value: root.selectedDevice?.paired ? qsTr("Vinculado") : qsTr("No vinculado") }
                            DetailRow { label: qsTr("Dirección"); value: root.selectedDevice?.address ?? qsTr("No disponible") }
                            CortetsuText {
                                Layout.fillWidth: true
                                visible: root.selectedDevice?.batteryAvailable ?? false
                                text: qsTr("Batería · %1%").arg(Math.round((root.selectedDevice?.battery ?? 0) * 100))
                                textSize: CortetsuTypography.labelSmallPx
                                color: CortetsuDesign.colorOnSurfaceVariant
                            }
                            CortetsuProgressBar {
                                Layout.fillWidth: true
                                visible: root.selectedDevice?.batteryAvailable ?? false
                                value: root.selectedDevice?.battery ?? 0
                                fillColor: (root.selectedDevice?.battery ?? 1) < 0.20
                                    ? CortetsuDesign.colorWarning
                                    : CortetsuDesign.colorPrimary
                                barHeight: 5
                            }
                        }
                    }
                }

                CortetsuStateMessage {
                    anchors.centerIn: parent
                    visible: !root.selectedDevice
                    kind: "empty"
                    icon: "bluetooth"
                    title: qsTr("Selecciona un dispositivo")
                    detail: qsTr("El detalle mostrará conexión, emparejamiento y batería cuando exista")
                }
            }
        }
    }

    component DetailRow: RowLayout {
        id: detailRow
        required property string label
        required property string value
        Layout.fillWidth: true
        spacing: CortetsuDesign.spacingStandard
        CortetsuText {
            Layout.fillWidth: true
            text: detailRow.label
            textSize: CortetsuTypography.bodySmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
        }
        CortetsuText {
            Layout.minimumWidth: 160
            text: detailRow.value
            textSize: CortetsuTypography.bodySmallPx
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
        }
    }
}
