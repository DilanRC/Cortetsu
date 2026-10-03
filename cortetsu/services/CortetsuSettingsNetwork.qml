pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Io
import "ConnectivityPolicy.js" as Policy
import Quickshell

Singleton {
    id: root
    readonly property var networks: ConnectivityWifi.networks
    readonly property var profiles: ConnectivityWifi.profiles
    readonly property bool wifiEnabled: ConnectivityWifi.wifiEnabled
    readonly property string activeSsid: ConnectivityWifi.activeNetwork?.name || ""
    readonly property string activeDevice: ConnectivityWifi.wifiDevice?.name || ""
    readonly property var activeDetails: ConnectivityWifi.details[activeDevice] || ({ device: activeDevice, address: "", gateway: "", dns: [] })
    readonly property string state: ["failed", "auth-required"].includes(operation.state) ? "error" : busy ? "loading" : "ready"
    readonly property var operation: ConnectivityWifi.operation
    readonly property string error: operation.lastError
    readonly property bool busy: ConnectivityWifi.busy
    readonly property string detailsState: ConnectivityWifi.detailsState === "failed" ? "error" : ConnectivityWifi.detailsState
    readonly property string detailsError: ConnectivityWifi.metadataError
    readonly property string lastMessage: operation.id > 0 && ["connected", "idle"].includes(operation.state)
        ? operation.kind === "connect" ? qsTr("Conexión confirmada")
            : operation.kind === "forget" ? qsTr("Perfil eliminado")
            : operation.kind === "ipv4" ? qsTr("Configuración guardada; reconecta para aplicarla")
            : operation.kind === "autoconnect" ? qsTr("Conexión automática actualizada")
            : operation.kind === "enable" ? (wifiEnabled ? qsTr("Wi-Fi activado") : qsTr("Wi-Fi apagado"))
            : qsTr("Desconexión confirmada") : ""
    property string secretState: "idle"
    property string secretError: ""
    property var passwordCopyProcess: null
    readonly property bool secretBusy: !!passwordCopyProcess

    function copyPassword(uuid) {
        if (secretBusy || !Policy.validUuid(uuid) || !profiles.some(profile => profile.uuid === uuid)) return;
        secretState = "loading";
        secretError = "";
        passwordCopyProcess = passwordCopyComponent.createObject(root, { profileUuid: uuid });
        copyDeadline.restart();
        passwordCopyProcess.running = true;
    }
    function cancelPasswordCopy() {
        copyDeadline.stop();
        if (passwordCopyProcess) {
            const process = passwordCopyProcess;
            passwordCopyProcess = null;
            process.destroy();
        }
        secretState = "idle";
        secretError = "";
    }
    function finishPasswordCopy(process, exitCode) {
        if (passwordCopyProcess !== process) return;
        copyDeadline.stop();
        passwordCopyProcess = null;
        const secret = exitCode === 0 ? process.passwordReader.text.replace(/\r?\n$/, "") : "";
        if (!secret.length) {
            secretState = "error";
            secretError = qsTr("No se pudo copiar la contraseña de este perfil");
        } else { Quickshell.clipboardText = secret; secretState = "ready"; }
        process.destroy();
    }
    // The collector is destroyed with its one-shot query; no secret survives in service state.
    readonly property Component passwordCopyComponent: Component {
        // startup inventory: cortetsu:network-password-copy
        Process {
            id: passwordCopy
            required property string profileUuid
            command: ["nmcli", "--wait", "5", "--show-secrets", "--escape", "no", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", profileUuid]
            environment: ({ LC_ALL: "C", LANG: "C" })
            readonly property StdioCollector passwordReader: StdioCollector {}
            stdout: passwordReader
            onExited: exitCode => root.finishPasswordCopy(passwordCopy, exitCode)
            onRunningChanged: if (!running && root.passwordCopyProcess === passwordCopy) root.finishPasswordCopy(passwordCopy, 127)
        }
    }
    readonly property Timer copyDeadline: Timer {
        interval: 6000
        onTriggered: {
            if (!root.passwordCopyProcess) return;
            root.passwordCopyProcess.signal(9);
            root.secretError = qsTr("NetworkManager tardó demasiado");
        }
    }
    Component.onDestruction: cancelPasswordCopy()
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
