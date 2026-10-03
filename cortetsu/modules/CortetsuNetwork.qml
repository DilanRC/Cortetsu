pragma Singleton

import Quickshell
import "../services"

Singleton {
    readonly property var wifiDevice: ConnectivityWifi.wifiDevice
    readonly property var activeWifiNetwork: ConnectivityWifi.activeNetwork
    readonly property var active: ConnectivityWifi.active
    readonly property var activeEthernet: ConnectivityWifi.activeEthernet
    readonly property bool connecting: ConnectivityWifi.connecting
    readonly property bool refreshing: ConnectivityWifi.scanning
    function refresh() { ConnectivityWifi.refresh(); }
    function strengthPercent(raw) { return ConnectivityWifi.strengthPercent(raw); }
}
