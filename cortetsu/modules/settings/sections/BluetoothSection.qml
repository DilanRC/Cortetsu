pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../../components"
import "../../../services"
import "../../../theme"
import "../.."
import "../controls"

ColumnLayout {
    id: root

    required property var context

    readonly property var bluetooth: root.context.bluetooth
    readonly property var operation: bluetooth.operation
    readonly property bool powerBusy: bluetooth.busy && operation.kind === "power"

    // What pressing the row does to a device, named before it is pressed.
    function actionFor(device): string {
        if (device.connected)
            return qsTr("Desconectar");
        return device.paired ? qsTr("Conectar") : qsTr("Emparejar");
    }

    function stateFor(device): string {
        if (root.bluetooth.busy && root.bluetooth.operationTarget === device)
            return qsTr("En curso…");
        if (device.connected)
            return qsTr("Conectado");
        return device.paired ? qsTr("Emparejado") : qsTr("Sin emparejar");
    }

    function act(device): void {
        if (device.adapter !== root.bluetooth.adapter)
            root.bluetooth.selectAdapter(device.adapter);
        if (device.connected)
            root.bluetooth.disconnectDevice(device);
        else if (device.paired)
            root.bluetooth.connectDevice(device);
        else
            root.bluetooth.pairDevice(device);
    }

    spacing: CortetsuDesign.spacingSection

    SettingsGroup {
        title: qsTr("Adaptador")

        CortetsuStateMessage {
            objectName: "noAdapter"
            Layout.fillWidth: true
            Layout.margins: CortetsuDesign.spacingSection
            visible: !root.bluetooth.adapter
            kind: "empty"
            icon: "bluetooth_disabled"
            title: qsTr("No hay adaptador Bluetooth")
            detail: qsTr("BlueZ no informa de ningún adaptador en este equipo")
        }

        SettingToggleRow {
            objectName: "bluetoothPower"
            visible: !!root.bluetooth.adapter
            title: qsTr("Bluetooth")
            detail: root.bluetooth.enabled ? qsTr("Encendido") : qsTr("Apagado")
            checked: root.bluetooth.enabled
            status: root.powerBusy ? "busy" : root.operation.state === "failed" && root.operation.kind === "power" ? "error" : ""
            statusText: root.powerBusy ? qsTr("Aplicando…") : root.operation.lastError
            onToggled: value => root.bluetooth.setEnabled(value)
        }
    }

    SettingsGroup {
        title: qsTr("Dispositivos")
        detail: qsTr("Conocidos por este equipo")
        visible: !!root.bluetooth.adapter && root.bluetooth.enabled

        SettingValueRow {
            objectName: "noDevices"
            visible: (root.bluetooth.allDevices ?? []).length === 0
            title: qsTr("Ningún dispositivo conocido")
            detail: qsTr("Los dispositivos emparejados aparecen aquí")
        }

        Repeater {
            model: ScriptModel { values: root.bluetooth.allDevices ?? [] }

            delegate: SettingActionRow {
                required property var modelData
                readonly property bool failed: root.operation.state === "failed" && root.operation.target === modelData
                title: modelData.name || qsTr("Dispositivo Bluetooth")
                detail: root.stateFor(modelData)
                status: failed ? "error" : root.bluetooth.busy && root.bluetooth.operationTarget === modelData ? "busy" : ""
                statusText: failed ? root.operation.lastError : qsTr("En curso…")
                actionLabel: root.actionFor(modelData)
                actionIcon: modelData.connected ? "link_off" : "link"
                disabled: root.bluetooth.busy
                onActivated: root.act(modelData)
            }
        }
    }
}
