pragma Singleton
import Quickshell

// Retained name for external imports. Network UI uses Connectivity directly.
Singleton {
    readonly property bool wifiEnabled: Connectivity.wifi.wifiEnabled
    readonly property var networks: Connectivity.wifi.networks
    readonly property var active: Connectivity.wifi.active
    readonly property var activeEthernet: Connectivity.wifi.activeEthernet
    readonly property bool scanning: Connectivity.wifi.scanning
    function toggleWifi() { Connectivity.wifi.setEnabled(!wifiEnabled); }
    function enableWifi(value) { Connectivity.wifi.setEnabled(value); }
    function rescanWifi() { Connectivity.wifi.refresh(); }
}
