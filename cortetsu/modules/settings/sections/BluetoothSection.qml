pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../../../components"
import "../.."
import "../../../services"
import "../../CortetsuDesign.js" as CortetsuDesign

ColumnLayout {
    id: root

    required property var page

    spacing: CortetsuDesign.spacingStandard

    CortetsuSectionHeader {
        Layout.fillWidth: true
        title: qsTr("Bluetooth")
        detail: qsTr("Estado nativo del adaptador")
    }

    DomainHero {
        icon: root.page.bluetoothConnected > 0 ? "bluetooth_connected" : "bluetooth"
        title: root.page.bluetoothEnabled ? qsTr("Bluetooth preparado") : qsTr("Bluetooth desactivado")
        detail: qsTr("Dispositivos gestionados por BlueZ")
        value: qsTr("%1 conectados").arg(root.page.bluetoothConnected)
        meta: Connectivity.bluetooth.adapter
            ? qsTr("%1 dispositivos conocidos").arg(Connectivity.bluetooth.allDevices?.length ?? 0)
            : qsTr("No hay adaptador disponible")
        warningState: !Connectivity.bluetooth.adapter || !root.page.bluetoothEnabled
    }

    StatusCard {
        title: qsTr("Dispositivos")
        value: root.page.bluetoothEnabled
            ? root.page.bluetoothConnected > 0
                ? qsTr("%1 conectados").arg(root.page.bluetoothConnected)
                : qsTr("Listo")
            : qsTr("Bluetooth apagado")
        detail: root.page.bluetoothEnabled ? qsTr("Adaptador activado") : qsTr("Adaptador desactivado")
        icon: root.page.bluetoothConnected > 0 ? "bluetooth_connected" : "bluetooth"
        activeState: root.page.bluetoothEnabled
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: root.page.bluetoothEnabled
        spacing: 0

        CortetsuSectionHeader {
            Layout.fillWidth: true
            title: qsTr("Dispositivos conocidos")
            detail: qsTr("Selecciona un dispositivo para conectar o desconectar")
        }

        Repeater {
            model: Connectivity.bluetooth.allDevices ?? []
            delegate: CortetsuListRow {
                required property var modelData
                Layout.fillWidth: true
                title: modelData.name ?? qsTr("Dispositivo Bluetooth")
                subtitle: modelData.connected ? qsTr("Conectado · pulsa para desconectar") : qsTr("Disponible · pulsa para conectar")
                icon: modelData.connected ? "bluetooth_connected" : "bluetooth"
                selected: modelData.connected
                enabled: !Connectivity.bluetooth.busy
                onClicked: {
                    if (modelData.adapter !== Connectivity.bluetooth.adapter) Connectivity.bluetooth.selectAdapter(modelData.adapter);
                    modelData.connected ? Connectivity.bluetooth.disconnectDevice(modelData) : (modelData.paired ? Connectivity.bluetooth.connectDevice(modelData) : Connectivity.bluetooth.pairDevice(modelData));
                }
            }
        }

        CortetsuStateMessage {
            Layout.fillWidth: true
            visible: (Connectivity.bluetooth.allDevices ?? []).length === 0
            kind: "empty"
            title: qsTr("No hay dispositivos conocidos")
            detail: qsTr("Empareja un dispositivo desde tu herramienta Bluetooth del sistema para verlo aquí")
        }
    }

    PreferenceToggle {
        title: qsTr("Adaptador Bluetooth")
        detail: qsTr("Activar o desactivar el adaptador predeterminado")
        icon: "bluetooth"
        checked: root.page.bluetoothEnabled
        controlDisabled: !Connectivity.bluetooth.adapter || Connectivity.bluetooth.busy
        onChanged: checked => {
            if (Connectivity.bluetooth.adapter)
                Connectivity.bluetooth.setEnabled(checked);
        }
    }
}
