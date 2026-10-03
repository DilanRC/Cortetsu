import QtQuick
import Quickshell.Networking
import "../services"

QtObject {
    function handleConnect(network, session, onPasswordNeeded): void {
        if (!network) return;
        if (network.security === WifiSecurityType.Open || network.known)
            Connectivity.wifi.connectNetwork(network, "", null);
        else if (onPasswordNeeded) onPasswordNeeded(network);
        else if (session?.network) {
            session.network.pendingNetwork = network;
            session.network.showPasswordDialog = true;
        }
    }
    function connectToNetwork(network, session, onPasswordNeeded): void { handleConnect(network, session, onPasswordNeeded); }
    function connectWithPassword(network, password, onResult): void {
        if (!network) return;
        Connectivity.wifi.connectNetwork(network, password || "", null);
        // Completion is observed through Connectivity.wifi.operation; a request is not success.
    }
}
