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
    // A copied password lives this long on the clipboard unless something else
    // is copied first.
    readonly property int secretClipboardLifetime: 45000

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
        process.destroy();
        if (!secret.length) {
            secretState = "error";
            secretError = qsTr("No se pudo copiar la contraseña de este perfil");
            return;
        }
        releaseSecretClipboard();
        secretClipboard = secretClipboardComponent.createObject(root, { secret: secret });
        secretClipboard.running = true;
    }
    // wl-copy --sensitive offers x-kde-passwordManagerHint, so `wl-paste
    // --watch` hands clipse CLIPBOARD_STATE=sensitive and clipse skips the
    // entry. Quickshell.clipboardText has no such hint and ends up in the
    // persistent history. --foreground keeps wl-copy alive exactly while it
    // owns the selection: it exits on its own when anything else is copied, so
    // ending it at the deadline can never erase what the user copied later.
    property var secretClipboard: null
    function releaseSecretClipboard() {
        secretExpiry.stop();
        if (!secretClipboard) return;
        const process = secretClipboard;
        secretClipboard = null;
        // Destroyed from its exit handler; destroying now would SIGKILL it.
        if (process.running) process.signal(15);
        else process.destroy();
    }
    function finishSecretClipboard(process, exitCode) {
        if (process.finished) return;
        process.finished = true;
        Qt.callLater(() => process.destroy());
        if (secretClipboard !== process) return;
        const offered = process.offered;
        secretClipboard = null;
        secretExpiry.stop();
        if (!offered) {
            secretState = "error";
            secretError = qsTr("No se pudo copiar de forma segura: wl-copy no está disponible");
        } else if (exitCode !== 0) {
            secretState = "error";
            secretError = qsTr("No se pudo copiar de forma segura");
        } else if (secretState === "ready") {
            secretState = "idle";
        }
    }
    readonly property Component secretClipboardComponent: Component {
        // startup inventory: cortetsu:network-password-clipboard
        Process {
            id: secretCopy
            property string secret
            property bool offered: false
            property bool finished: false
            command: ["wl-copy", "--foreground", "--sensitive", "--type", "text/plain;charset=utf-8"]
            stdinEnabled: true
            onStarted: {
                write(secret);
                secret = "";
                // Closing stdin is what makes wl-copy take the selection.
                stdinEnabled = false;
                offered = true;
                root.secretState = "ready";
                secretExpiry.restart();
            }
            onExited: exitCode => root.finishSecretClipboard(secretCopy, exitCode)
            onRunningChanged: if (!running && root.secretClipboard === secretCopy) root.finishSecretClipboard(secretCopy, offered ? 0 : 127)
        }
    }
    readonly property Timer secretExpiry: Timer {
        interval: root.secretClipboardLifetime
        onTriggered: {
            root.releaseSecretClipboard();
            if (root.secretState === "ready") root.secretState = "idle";
        }
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
    Component.onDestruction: { cancelPasswordCopy(); releaseSecretClipboard(); }
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
