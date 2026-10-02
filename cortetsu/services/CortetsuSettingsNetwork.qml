pragma Singleton

import Quickshell

Singleton {
    readonly property var networks: ConnectivityWifi.networks
    readonly property var profiles: ConnectivityWifi.profiles
    readonly property bool wifiEnabled: ConnectivityWifi.wifiEnabled
    readonly property string activeSsid: ConnectivityWifi.activeNetwork?.name || ""
    readonly property string activeDevice: ConnectivityWifi.wifiDevice?.name || ""
    readonly property var activeDetails: ConnectivityWifi.details[activeDevice] || ({ device: activeDevice, address: "", gateway: "", dns: [] })
    readonly property string state: ConnectivityWifi.operation.state
    readonly property var operation: ConnectivityWifi.operation
    readonly property string error: operation.lastError
    readonly property bool busy: ConnectivityWifi.busy
    readonly property string detailsState: ConnectivityWifi.detailsState
    readonly property string detailsError: ConnectivityWifi.metadataError
    function refresh() { ConnectivityWifi.refresh(); }
    function refreshAll() { ConnectivityWifi.refresh(); }
    function refreshNetworks() { ConnectivityWifi.refresh(); }
    function refreshProfiles() { ConnectivityWifi.refreshProfiles(); }
    function refreshDetails(device) { ConnectivityWifi.refreshDetails(device); }
    function setWifi(enabled) { ConnectivityWifi.setEnabled(enabled); }
    function connectNetwork(network, password, profile) { ConnectivityWifi.connectNetwork(network, password, profile); }
    function disconnectNetwork(network) { ConnectivityWifi.disconnectNetwork(network); }
    function forget(uuid) { ConnectivityWifi.forgetProfile(uuid); }
    function setAutoconnect(uuid, enabled) { ConnectivityWifi.setAutoconnect(uuid, enabled); }
}
