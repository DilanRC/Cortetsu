pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../../../services"
import "../../../components"
import "../../../theme"
import "../.."
import "../../settings/bluetooth/BluetoothDevices.js" as Devices

CortetsuPopupSurface {
    id: root
    readonly property string scanOwner: "bluetooth-" + String(root)

    required property var popouts
    implicitWidth: 336
    implicitHeight: body.implicitHeight + CortetsuDesign.spacingComfortable * 2

    readonly property bool adapterEnabled: ConnectivityBluetooth.enabled ?? false
    readonly property var devices: [...ConnectivityBluetooth.devices].sort((a, b) =>
        (b.connected - a.connected) || (b.paired - a.paired) || a.name.localeCompare(b.name))
    readonly property int connectedCount: root.devices.filter(device => device.connected).length

    Component.onCompleted: ConnectivityBluetooth.setScanOwner(root.scanOwner, visible)
    onVisibleChanged: ConnectivityBluetooth.setScanOwner(root.scanOwner, visible)
    Component.onDestruction: ConnectivityBluetooth.setScanOwner(root.scanOwner, false)

    ColumnLayout {
        id: body
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingComfortable
        spacing: CortetsuDesign.spacingStandard

        // One line instead of a header plus a card that repeated it.
        CortetsuPopoutHeader {
            icon: "bluetooth"
            title: qsTr("Bluetooth")
            detail: !ConnectivityBluetooth.adapter ? qsTr("Sin adaptador")
                : !root.adapterEnabled ? qsTr("Apagado")
                : root.connectedCount === 1 ? qsTr("1 conectado")
                : root.connectedCount > 1 ? qsTr("%1 conectados").arg(root.connectedCount)
                : qsTr("Encendido")
            settingsPage: "bluetooth"
            popouts: root.popouts

            CortetsuToggle {
                objectName: "popoutBluetoothPower"
                visible: !!ConnectivityBluetooth.adapter
                accessibleName: qsTr("Bluetooth")
                checked: root.adapterEnabled
                disabled: ConnectivityBluetooth.busy
                onToggled: checked => ConnectivityBluetooth.setEnabled(checked)
            }
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: !root.adapterEnabled || root.devices.length === 0
            // Off by choice is a state, not an error.
            kind: !ConnectivityBluetooth.adapter ? "error" : "empty"
            icon: root.adapterEnabled ? "devices_other" : "bluetooth_disabled"
            title: !ConnectivityBluetooth.adapter ? qsTr("No hay adaptador Bluetooth")
                : root.adapterEnabled ? qsTr("No hay dispositivos cerca") : qsTr("Bluetooth está apagado")
            detail: !ConnectivityBluetooth.adapter ? qsTr("BlueZ no informa de ningún adaptador")
                : root.adapterEnabled
                ? qsTr("Los dispositivos vinculados y detectados aparecerán aquí")
                : qsTr("Enciéndelo arriba para conectar dispositivos")
        }

        CortetsuSectionHeader {
            visible: root.adapterEnabled && root.devices.length > 0
            title: qsTr("Dispositivos")
            detail: root.devices.length === 1 ? qsTr("1 disponible") : qsTr("%1 disponibles").arg(root.devices.length)
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: ConnectivityBluetooth.operation.state === "failed"
            kind: "error"
            title: qsTr("La operación Bluetooth falló")
            detail: ConnectivityBluetooth.operation.lastError
        }

        ListView {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(contentHeight, 5 * CortetsuDesign.rowHeight)
            visible: root.adapterEnabled && root.devices.length > 0
            clip: true
            spacing: CortetsuDesign.spacingUnit
            model: root.devices
            delegate: CortetsuListRow {
                // A BlueZ device, read through its properties only.
                required property var modelData
                width: ListView.view.width
                // Battery only when BlueZ reports it; never guessed.
                readonly property int battery: Devices.batteryPercent(modelData)
                icon: Devices.icon(modelData)
                title: Devices.displayName(modelData)
                subtitle: (modelData.connected
                    ? qsTr("Conectado")
                    : modelData.paired
                        ? qsTr("Vinculado · pulsa para conectar")
                        : qsTr("Disponible · pulsa para emparejar"))
                    + (battery >= 0 ? qsTr(" · batería %1 %").arg(battery) : "")
                selected: modelData.connected
                enabled: !ConnectivityBluetooth.busy
                onClicked: {
                    if (modelData.connected)
                        ConnectivityBluetooth.disconnectDevice(modelData);
                    else
                        modelData.paired ? ConnectivityBluetooth.connectDevice(modelData) : ConnectivityBluetooth.pairDevice(modelData);
                }
            }
        }
    }
}
