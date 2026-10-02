pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../components"
import "../../services"
import "../CortetsuDesign.js" as Design

Item {
    id: root
    required property var screenState
    required property var screen
    readonly property var bluetooth: Connectivity.bluetooth
    property var selectedDevice: null
    property string confirmForgetAddress: ""
    readonly property string scanOwner: "settings-bluetooth-" + String(root)
    implicitHeight: body.implicitHeight
    onVisibleChanged: bluetooth.setScanOwner(scanOwner, visible)
    Component.onCompleted: bluetooth.setScanOwner(scanOwner, visible)
    Component.onDestruction: bluetooth.setScanOwner(scanOwner, false)
    Connections {
        target: root.bluetooth
        function onDevicesChanged(): void {
            if (root.selectedDevice && !root.bluetooth.devices.includes(root.selectedDevice))
                root.selectedDevice = null;
        }
    }
    function stateLabel(device): string {
        const op = bluetooth.operation;
        if (op.target === device) {
            if (op.state === "failed") return op.lastError;
            if (op.state === "pending")
                return op.kind === "pair" ? qsTr("Emparejando…")
                    : op.kind === "connect" ? qsTr("Conectando…")
                    : op.kind === "disconnect" ? qsTr("Desconectando…") : qsTr("Olvidando…");
        }
        return device.connected ? qsTr("Conectado") : bluetooth.propertyValue(device, "blocked") ? qsTr("Bloqueado")
            : device.paired || device.bonded ? qsTr("Guardado") : qsTr("Disponible para emparejar");
    }
    component DeviceGroup: ColumnLayout {
        id: group
        required property string heading
        required property var entries
        Layout.fillWidth: true
        spacing: Design.spacingUnit
        CortetsuSectionHeader { Layout.fillWidth: true; title: group.heading; detail: String(group.entries.length) }
        Repeater {
            model: group.entries
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name || modelData.address
                subtitle: root.stateLabel(modelData) + (modelData.batteryAvailable ? " · " + Math.round(modelData.battery * 100) + "%" : "")
                icon: modelData.connected ? "bluetooth_connected" : "bluetooth"
                selected: modelData === root.selectedDevice
                onClicked: { root.selectedDevice = modelData; root.confirmForgetAddress = ""; }
            }
        }
    }
    ColumnLayout {
        id: body
        width: parent.width
        spacing: Design.spacingStandard
        RowLayout {
            Layout.fillWidth: true
            CortetsuSectionHeader { Layout.fillWidth: true; title: qsTr("Bluetooth"); detail: root.bluetooth.discovering ? qsTr("Buscando dispositivos…") : qsTr("Dispositivos y adaptadores") }
            CortetsuToggle {
                checked: root.bluetooth.enabled
                disabled: !root.bluetooth.adapter
                onToggled: value => root.bluetooth.setEnabled(value)
                Accessible.name: qsTr("Activar Bluetooth")
            }
        }
        RowLayout {
            Layout.fillWidth: true
            visible: root.bluetooth.adapters.length > 1
            Repeater {
                model: root.bluetooth.adapters
                delegate: CortetsuButton {
                    required property var modelData
                    label: modelData.name
                    icon: "bluetooth"
                    active: root.bluetooth.adapter === modelData
                    onClicked: root.bluetooth.selectAdapter(modelData)
                }
            }
        }
        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: !root.bluetooth.adapter || !root.bluetooth.enabled
            title: !root.bluetooth.adapter ? qsTr("Adaptador no disponible") : qsTr("Bluetooth desactivado")
            detail: !root.bluetooth.adapter ? qsTr("Comprueba el hardware y el servicio BlueZ") : ""
        }
        DeviceGroup { heading: qsTr("Conectados"); entries: root.bluetooth.devices.filter(device => device.connected) }
        DeviceGroup { heading: qsTr("Dispositivos guardados"); entries: root.bluetooth.devices.filter(device => !device.connected && (device.paired || device.bonded)) }
        DeviceGroup { heading: qsTr("Dispositivos cercanos"); entries: root.bluetooth.devices.filter(device => !device.connected && !device.paired && !device.bonded) }
        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: root.bluetooth.enabled && root.bluetooth.devices.length === 0
            title: qsTr("Sin resultados todavía")
            detail: qsTr("Activa el modo de emparejamiento del dispositivo. La búsqueda se detiene al salir de esta página.")
        }
        CortetsuSurface {
            Layout.fillWidth: true
            visible: !!root.selectedDevice
            implicitHeight: inspector.implicitHeight + Design.spacingComfortable * 2
            baseColor: Qt.alpha(Design.colorSurfaceGlass, 0.72)
            outlined: true
            radiusValue: Design.radiusMedium
            ColumnLayout {
                id: inspector
                anchors.fill: parent
                anchors.margins: Design.spacingComfortable
                spacing: Design.spacingCompact
                CortetsuSectionHeader { title: root.selectedDevice?.name ?? ""; detail: root.selectedDevice ? root.stateLabel(root.selectedDevice) : "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Dirección"); value: root.selectedDevice?.address ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Tipo"); value: root.selectedDevice?.icon ?? "" }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Batería"); value: root.selectedDevice?.batteryAvailable ? Math.round(root.selectedDevice.battery * 100) + "%" : qsTr("El dispositivo no informa batería") }
                ConnectionDetail { Layout.fillWidth: true; label: qsTr("Emparejado / vínculo persistente"); value: root.selectedDevice ? (root.selectedDevice.paired ? qsTr("Sí") : qsTr("No")) + " / " + (root.selectedDevice.bonded ? qsTr("Sí") : qsTr("No")) : "" }
                RowLayout {
                    Layout.fillWidth: true
                    CortetsuText { Layout.fillWidth: true; text: qsTr("Dispositivo de confianza"); textSize: Design.bodySmallPx }
                    CortetsuToggle { checked: Connectivity.bluetooth.propertyValue(root.selectedDevice, "trusted"); onToggled: value => root.bluetooth.setTrusted(root.selectedDevice, value); Accessible.name: qsTr("Confiar en el dispositivo") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    CortetsuText { Layout.fillWidth: true; text: qsTr("Bloqueado"); textSize: Design.bodySmallPx }
                    CortetsuToggle { checked: Connectivity.bluetooth.propertyValue(root.selectedDevice, "blocked"); onToggled: value => root.bluetooth.setBlocked(root.selectedDevice, value); Accessible.name: qsTr("Bloquear el dispositivo") }
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Design.spacingCompact
                    CortetsuButton {
                        label: root.selectedDevice?.connected ? qsTr("Desconectar") : qsTr("Conectar / reintentar")
                        icon: "link"
                        disabled: root.bluetooth.busy || !root.selectedDevice || root.bluetooth.propertyValue(root.selectedDevice, "blocked") || !root.bluetooth.enabled
                        onClicked: root.selectedDevice.connected ? root.bluetooth.disconnectDevice(root.selectedDevice) : root.bluetooth.connectDevice(root.selectedDevice)
                    }
                    CortetsuButton {
                        label: qsTr("Emparejar")
                        icon: "add_link"
                        disabled: root.bluetooth.busy || !root.selectedDevice || root.selectedDevice.paired || root.bluetooth.propertyValue(root.selectedDevice, "blocked") || !root.bluetooth.enabled
                        onClicked: root.bluetooth.pairDevice(root.selectedDevice)
                    }
                    CortetsuButton { label: qsTr("Cancelar emparejamiento"); icon: "close"; visible: root.bluetooth.busy && root.bluetooth.operation.kind === "pair"; onClicked: root.bluetooth.cancelPair() }
                    CortetsuButton {
                        label: root.confirmForgetAddress === root.selectedDevice?.address ? qsTr("Confirmar olvido") : qsTr("Olvidar")
                        icon: "delete"
                        danger: true
                        disabled: root.bluetooth.busy || !root.selectedDevice || root.selectedDevice.connected
                        onClicked: {
                            if (root.confirmForgetAddress === root.selectedDevice.address) {
                                root.bluetooth.forgetDevice(root.selectedDevice);
                                root.selectedDevice = null;
                            } else root.confirmForgetAddress = root.selectedDevice.address;
                        }
                    }
                }
                CortetsuText {
                    Layout.fillWidth: true
                    text: root.bluetooth.authenticationNotice
                    textSize: Design.bodySmallPx
                    color: Design.colorOnSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
