pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root
    readonly property var wifi: ConnectivityWifi
    readonly property var bluetooth: ConnectivityBluetooth
    readonly property var vpn: VPN
    readonly property string internetLabel: wifi.connectivity === "full" ? qsTr("Acceso a Internet")
        : wifi.connectivity === "limited" ? qsTr("Conectividad limitada")
        : wifi.connectivity === "portal" ? qsTr("Portal cautivo")
        : wifi.connectivity === "none" ? qsTr("Sin acceso a Internet") : qsTr("Internet sin comprobar")
    Connections {
        target: root.wifi
        function onOperationChanged(): void {
            const op = root.wifi.operation;
            if (op.kind === "connect" && op.state === "connected")
                CortetsuToaster.toast(qsTr("Red conectada"), op.target.ssid || root.wifi.activeNetwork?.name || "", "wifi");
        }
    }
    Connections {
        target: root.bluetooth
        function onOperationChanged(): void {
            const op = root.bluetooth.operation;
            if (op.kind === "connect" && op.state === "succeeded" && op.target?.connected)
                CortetsuToaster.toast(qsTr("Bluetooth conectado"), op.target.name, "bluetooth_connected");
        }
    }
}
