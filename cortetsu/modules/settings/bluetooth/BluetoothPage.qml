pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../../../services"
import "../.."
import "../../../theme"
import "../controls"
import "BluetoothDevices.js" as Devices

// Bluetooth is a device manager laid out like Wi-Fi: the adapter on top, the
// explorer on the left and the selected device's inspector on the right. Every
// control calls ConnectivityBluetooth; nothing here keeps its own copy of BlueZ.
Item {
    id: root

    required property var context

    readonly property var bluetooth: root.context.bluetooth
    readonly property var operation: bluetooth.operation
    readonly property var adapter: bluetooth.adapter
    readonly property bool ready: !!adapter && bluetooth.enabled
    // Discovery runs while this page is on screen and stops when it leaves.
    readonly property string scanOwner: "settings-bluetooth-" + String(root)
    readonly property bool powerBusy: bluetooth.busy && operation.kind === "power"
    readonly property bool compactLayout: width < 760

    property string filter: "all"
    property string query: ""
    property string selectedPath: ""

    // Only the selected adapter's devices: actions run on that adapter.
    readonly property var devices: root.ready ? [...(bluetooth.devices ?? [])] : []
    readonly property var shownDevices: Devices.visible(root.devices, root.filter, root.query)
    readonly property var selectedDevice: root.shownDevices.find(device => device.dbusPath === root.selectedPath)
        ?? root.shownDevices[0] ?? null

    implicitHeight: (root.compactLayout ? 1120 : 600) + header.implicitHeight + CortetsuDesign.spacingStandard

    function property(device, name): bool {
        return root.bluetooth.propertyValue ? root.bluetooth.propertyValue(device, name) : !!device?.[name];
    }
    // Compared by BlueZ path: the same device can reach QML as two wrappers.
    function same(left, right): bool {
        return !!left && !!right && left.dbusPath === right.dbusPath;
    }
    function targets(device): bool {
        return root.same(root.operation.target, device);
    }
    function pending(device): bool {
        return root.bluetooth.busy && root.targets(device);
    }
    function failed(device): bool {
        return root.operation.state === "failed" && root.targets(device);
    }
    // The state line under a name; an operation in flight wins over the link.
    function stateText(device): string {
        if (root.pending(device)) {
            switch (root.operation.kind) {
            case "pair": return qsTr("Emparejando…");
            case "connect": return qsTr("Conectando…");
            case "disconnect": return qsTr("Desconectando…");
            case "forget": return qsTr("Olvidando…");
            default: return qsTr("Aplicando…");
            }
        }
        if (root.property(device, "blocked")) return qsTr("Bloqueado");
        if (device?.connected) return qsTr("Conectado");
        if (device?.paired || device?.bonded) return qsTr("Emparejado, sin conectar");
        return qsTr("Disponible para emparejar");
    }
    function primaryAction(device): void {
        if (!device || root.bluetooth.busy) return;
        if (device.connected) root.bluetooth.disconnectDevice(device);
        else if (device.paired || device.bonded) root.bluetooth.connectDevice(device);
        else root.bluetooth.pairDevice(device);
    }

    onVisibleChanged: bluetooth.setScanOwner?.(scanOwner, visible)
    Component.onCompleted: bluetooth.setScanOwner?.(scanOwner, visible)
    Component.onDestruction: bluetooth.setScanOwner?.(scanOwner, false)
    onFilterChanged: selectedPath = ""

    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingStandard

        SettingsGroup {
            id: header

            CortetsuStateMessage {
                objectName: "noAdapter"
                Layout.fillWidth: true
                Layout.margins: CortetsuDesign.spacingSection
                visible: !root.adapter
                kind: "empty"
                icon: "bluetooth_disabled"
                title: qsTr("No hay adaptador Bluetooth")
                detail: qsTr("BlueZ no informa de ningún adaptador en este equipo")
            }

            SettingToggleRow {
                objectName: "bluetoothPower"
                visible: !!root.adapter
                title: qsTr("Bluetooth")
                detail: !root.bluetooth.enabled ? qsTr("Apagado")
                    : root.bluetooth.connectedCount > 0
                        ? root.bluetooth.connectedCount === 1
                            ? qsTr("Encendido · 1 dispositivo conectado")
                            : qsTr("Encendido · %1 dispositivos conectados").arg(root.bluetooth.connectedCount)
                        : qsTr("Encendido")
                checked: root.bluetooth.enabled
                status: root.powerBusy ? "busy" : root.operation.state === "failed" && root.operation.kind === "power" ? "error" : ""
                statusText: root.powerBusy ? qsTr("Aplicando…") : root.operation.lastError
                onToggled: value => root.bluetooth.setEnabled(value)
            }

            SettingChoiceChips {
                objectName: "bluetoothAdapter"
                visible: root.ready && (root.bluetooth.adapters ?? []).length > 1
                title: qsTr("Adaptador")
                detail: qsTr("Las acciones y la búsqueda usan el adaptador elegido")
                options: (root.bluetooth.adapters ?? []).map(item => ({
                    value: item.dbusPath, label: item.name || item.adapterId || item.dbusPath, icon: "bluetooth"
                }))
                current: root.adapter?.dbusPath ?? ""
                disabled: root.bluetooth.busy
                onChosen: value => {
                    const next = root.bluetooth.adapters.find(item => item.dbusPath === value);
                    if (next) root.bluetooth.selectAdapter(next);
                }
            }

            SettingToggleRow {
                objectName: "bluetoothDiscoverable"
                visible: root.ready
                title: qsTr("Visible para otros dispositivos")
                detail: root.adapter?.discoverable
                    ? qsTr("Otros dispositivos encuentran este equipo como «%1»").arg(root.adapter?.name ?? "")
                    : qsTr("Este equipo no aparece en las búsquedas de otros")
                checked: root.adapter?.discoverable ?? false
                disabled: root.bluetooth.busy
                status: root.bluetooth.busy && root.operation.kind === "discoverable" ? "busy"
                    : root.operation.state === "failed" && root.operation.kind === "discoverable" ? "error" : ""
                statusText: root.bluetooth.busy ? qsTr("Aplicando…") : root.operation.lastError
                onToggled: value => root.bluetooth.setDiscoverable(value)
            }
        }

        Flow {
            id: workbench
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.ready
            spacing: CortetsuDesign.spacingSection
            height: root.compactLayout
                ? listPanel.implicitHeight + detailPanel.implicitHeight + spacing
                : Math.max(listPanel.implicitHeight, detailPanel.implicitHeight)

            DeviceListPanel {
                id: listPanel
                page: root
                width: root.compactLayout ? workbench.width : Math.min(390, Math.max(340, workbench.width * 0.34))
            }

            DeviceDetailPanel {
                id: detailPanel
                page: root
                width: root.compactLayout ? workbench.width : Math.max(0, workbench.width - listPanel.width - workbench.spacing)
            }
        }

        CortetsuStateMessage {
            objectName: "bluetoothOff"
            Layout.fillWidth: true
            Layout.topMargin: CortetsuDesign.spacingSection
            visible: !!root.adapter && !root.bluetooth.enabled
            kind: "empty"
            icon: "bluetooth_disabled"
            title: qsTr("Bluetooth está apagado")
            detail: qsTr("Enciéndelo para ver, emparejar y conectar dispositivos")
        }
    }
}
