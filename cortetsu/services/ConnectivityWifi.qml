pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Networking
import "ConnectivityPolicy.js" as Policy

Singleton {
    id: root
    signal backendEvent()
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevices: devices.filter(device => device.type === DeviceType.Wifi)
    readonly property var wifiDevice: wifiDevices.find(device => device.connected) || wifiDevices[0] || null
    // The installed native setter updates its cache before the D-Bus write succeeds.
    readonly property bool wifiEnabled: adapter.radioReady ? adapter.radioEnabled : Networking.wifiEnabled
    readonly property bool hardwareEnabled: Networking.wifiHardwareEnabled
    readonly property var networks: wifiDevices.reduce((result, device) => result.concat(device.networks.values), [])
    readonly property var activeNetwork: networks.find(network => network.connected) || null
    readonly property var active: activeNetwork ? { ssid: activeNetwork.name, strength: Policy.strengthPercent(activeNetwork.signalStrength) } : null
    readonly property var activeEthernet: devices.find(device => device.type === DeviceType.Wired && device.connected) || null
    readonly property bool connecting: wifiDevices.some(device => device.state === ConnectionState.Connecting)
        || operation.state === "connecting"
    readonly property string connectivity: Networking.connectivity === NetworkConnectivity.Full ? "full"
        : Networking.connectivity === NetworkConnectivity.Limited ? "limited"
        : Networking.connectivity === NetworkConnectivity.Portal ? "portal"
        : Networking.connectivity === NetworkConnectivity.None ? "none" : "unknown"
    readonly property var profiles: adapter.profiles
    readonly property var details: adapter.details
    readonly property var accessPoints: adapter.accessPoints
    readonly property string detailsState: adapter.detailsState
    readonly property string metadataError: adapter.lastError
    property var operation: Policy.operation(0, "", {}, "idle", 0)
    property int nextOperationId: 0
    property var operationNetwork: null
    readonly property var operationDevice: devices.find(device => device.name === operation.target.device) || null
    readonly property var observedNetwork: operationNetwork || (operation.kind === "connect" && operation.target.uuid
        ? (operationDevice?.type === DeviceType.Wired ? operationDevice.network : networks.find(network => network.device === operationDevice && network.connected) || null) : null)
    readonly property bool operationConnected: operation.kind === "disconnect-wired" ? operationDevice?.connected || false : observedNetwork?.connected || false
    property bool mutationAccepted: false
    property bool passwordProvided: false
    property string rawError: ""
    property var scanOwners: ({})
    readonly property bool scanning: wifiEnabled && hardwareEnabled && Object.keys(scanOwners).length > 0
    readonly property bool busy: ["connecting", "disconnecting", "forgetting", "changing"].includes(operation.state)

    function containsNetwork(network) { return network && networks.includes(network); }
    function begin(kind, target, state, network) {
        if (busy) return false;
        operationNetwork = network || null;
        mutationAccepted = false;
        passwordProvided = false;
        rawError = "";
        operation = Policy.operation(++nextOperationId, kind, target, state, Date.now());
        deadline.restart();
        return true;
    }
    function fail(code, message, retryable) {
        deadline.stop();
        adapter.cancelOperation(operation.id);
        operation = Policy.fail(operation, code, message, retryable);
    }
    function complete() {
        deadline.stop();
        operation = Object.assign({}, operation, { state: operation.kind === "connect" ? "connected" : "idle" });
        passwordProvided = false;
    }
    function observe() {
        if (!busy) return;
        if ((operation.kind === "disconnect" || (operation.kind === "connect" && !operation.target.uuid)) && !containsNetwork(operationNetwork)) {
            fail("ap-unavailable", qsTr("La red ya no está disponible"), true);
            return;
        }
        if (operation.kind === "disconnect-wired" && !operationDevice) { complete(); return; }
        const snapshot = {
            connected: operationConnected,
            uuid: details[operation.target.device || operationNetwork?.device?.name]?.uuid || "",
            enabled: wifiEnabled, profiles: profiles
        };
        if (["forget", "autoconnect", "ipv4"].includes(operation.kind) && !mutationAccepted) return;
        if (operation.target.uuid && operation.kind === "connect" && !mutationAccepted) return;
        if (Policy.confirmed(operation, snapshot)) complete();
    }
    function connectNetwork(network, password, profile) {
        if (!containsNetwork(network)) { if (begin("connect", {}, "connecting", null)) fail("ap-unavailable", qsTr("La red ya no está disponible"), true); return; }
        if (!begin("connect", { ssid: network.name, device: network.device.name, uuid: profile?.uuid || "" }, "connecting", network)) return;
        if (profile) {
            const saved = profiles.find(item => item.uuid === profile.uuid);
            if (!saved || saved.type !== "802-11-wireless" || saved.ssid !== network.name || (saved.interface && saved.interface !== network.device.name)) {
                fail("profile-invalid", qsTr("El perfil no corresponde a esta red y dispositivo"), false); return;
            }
        }
        if (!hardwareEnabled) { fail("rfkill", qsTr("Wi-Fi está bloqueado por hardware"), false); return; }
        if (!wifiEnabled) { fail("wifi-disabled", qsTr("Wi-Fi está apagado"), true); return; }
        const secret = password || "";
        if (secret && ![WifiSecurityType.WpaPsk, WifiSecurityType.Wpa2Psk, WifiSecurityType.Sae].includes(network.security)) {
            fail("unsupported-authentication", qsTr("Esta red requiere un perfil de autenticación avanzado"), false); return;
        }
        if (secret) {
            passwordProvided = true;
            const matching = profiles.filter(item => item.type === "802-11-wireless" && item.ssid === network.name
                && (!item.interface || item.interface === network.device.name));
            const targetProfile = profile || (matching.length === 1 ? matching[0] : null);
            if (!targetProfile && (matching.length > 1 || network.known)) {
                fail("ambiguous-profile", qsTr("Selecciona el perfil guardado antes de actualizar su contraseña"), false); return;
            }
            if (targetProfile) {
                operation = Object.assign({}, operation, { target: Object.assign({}, operation.target, { uuid: targetProfile.uuid }) });
                adapter.saveAndActivate(operation.id, targetProfile.uuid, network.device.name, secret);
            } else network.connectWithPsk(secret);
        } else if (profile?.uuid) adapter.mutate(operation.id, "connect", profile.uuid, false, network.device.name);
        else network.connect();
        observe();
    }
    function connectProfile(uuid, deviceName) {
        const profile = profiles.find(item => item.uuid === uuid);
        if (!profile) return;
        const candidates = devices.filter(item => item.type === (profile.type === "802-3-ethernet" ? DeviceType.Wired : DeviceType.Wifi));
        const device = Policy.profileDevice(candidates, profile, deviceName || "");
        if (!begin("connect", { uuid: uuid, ssid: profile.ssid, device: device?.name || "" }, "connecting", null)) return;
        if (!device) { fail("device-unavailable", qsTr("El dispositivo del perfil no está disponible"), true); return; }
        if (profile.type === "802-11-wireless" && (!wifiEnabled || !hardwareEnabled)) { fail("wifi-disabled", qsTr("Activa Wi-Fi antes de conectar"), true); return; }
        adapter.mutate(operation.id, "connect", uuid, false, device?.name || "");
    }
    function connectHidden(ssid, device, password, security) {
        const selected = wifiDevices.find(item => item.name === device) || (!device ? wifiDevice : null);
        const existing = Policy.hiddenRetryProfile(operation, profiles, ssid, selected?.name || "", security);
        if (!existing && Policy.hiddenRetryTarget(operation, ssid, selected?.name || "", security) && adapter.profileReadsPending) {
            operation = Object.assign({}, operation, {lastError: qsTr("Comprobando el perfil creado; vuelve a intentar cuando termine la actualización")});
            return;
        }
        const uuid = existing ? existing.uuid : Policy.newUuid();
        if (!begin("connect", { uuid: uuid, ssid: ssid, device: selected?.name || "", security: security, createdProfile: true }, "connecting", null)) return;
        if (!selected || !Policy.hiddenInput(ssid, security, password || "")) {
            fail("invalid-hidden-network", qsTr("Comprueba el SSID, el dispositivo y la seguridad de la red oculta"), false); return;
        }
        if (!wifiEnabled || !hardwareEnabled) { fail("wifi-disabled", qsTr("Activa Wi-Fi antes de conectar"), true); return; }
        passwordProvided = !!password;
        if (existing) {
            if (security === "open") adapter.mutate(operation.id, "connect", uuid, false, selected.name);
            else adapter.saveAndActivate(operation.id, uuid, selected.name, password || "");
        } else adapter.createHidden(operation.id, uuid, ssid, selected.name, security, password || "");
    }
    function disconnectWired(device) {
        if (!devices.includes(device) || device.type !== DeviceType.Wired) return;
        if (!begin("disconnect-wired", { device: device.name }, "disconnecting", null)) return;
        device.disconnect();
        observe();
    }
    function disconnectNetwork(network) {
        if (!containsNetwork(network)) return;
        if (!begin("disconnect", { ssid: network.name, device: network.device.name }, "disconnecting", network)) return;
        network.disconnect();
        observe();
    }
    function setEnabled(enabled) {
        if (!begin("enable", { enabled: enabled }, "changing", null)) return;
        if (enabled && !hardwareEnabled) { fail("rfkill", qsTr("Wi-Fi está bloqueado por hardware"), false); return; }
        Networking.wifiEnabled = enabled;
        adapter.refreshRadio();
        observe();
    }
    function forgetProfile(uuid) {
        if (!profiles.some(profile => profile.uuid === uuid)) return;
        if (begin("forget", { uuid: uuid }, "forgetting", null)) adapter.mutate(operation.id, "forget", uuid, false, "");
    }
    function setAutoconnect(uuid, enabled) {
        if (!profiles.some(profile => profile.uuid === uuid)) return;
        if (begin("autoconnect", { uuid: uuid, enabled: enabled }, "changing", null)) adapter.mutate(operation.id, "autoconnect", uuid, enabled, "");
    }
    function setIpv4(uuid, method, address, gateway, dns) {
        const config = Policy.ipv4Config(method, address, gateway, dns);
        if (!begin("ipv4", { uuid: uuid, config: config }, "changing", null)) return;
        if (!config || !profiles.some(profile => profile.uuid === uuid)) {
            fail("invalid-ipv4", qsTr("Comprueba la dirección IPv4, el prefijo, la puerta de enlace y los DNS"), false);
            return;
        }
        adapter.setIpv4(operation.id, uuid, config);
    }
    function setScanOwner(owner, enabled) {
        if (!owner) return;
        const next = Object.assign({}, scanOwners);
        if (enabled) next[owner] = true;
        else delete next[owner];
        scanOwners = next;
    }
    function syncScanners() {
        for (const device of wifiDevices) device.scannerEnabled = scanning;
    }
    function refresh() {
        adapter.ensureMonitor();
        if (wifiEnabled && hardwareEnabled) {
            setScanOwner("explicit-refresh", true);
            scanDeadline.restart();
        }
        adapter.refresh();
        if (wifiDevice) refreshDetails(wifiDevice.name);
    }
    function refreshDetails(device) { adapter.refreshDetails(device || wifiDevice?.name || ""); }
    function refreshProfiles() { adapter.refreshProfiles(true); }
    function strengthPercent(raw) { return Policy.strengthPercent(raw); }

    onScanningChanged: syncScanners()
    onWifiDevicesChanged: { syncScanners(); adapter.ensureMonitor(); adapter.refreshRadio(); observe(); }
    onNetworksChanged: observe()
    onOperationConnectedChanged: observe()
    onWifiEnabledChanged: observe()
    onProfilesChanged: observe()
    onDetailsChanged: observe()
    onActiveNetworkChanged: { if (wifiDevice) adapter.refreshDetails(wifiDevice.name); observe(); }

    Connections {
        target: Networking
        function onWifiEnabledChanged() { adapter.refreshRadio(); }
    }
    ConnectivityNmAdapter {
        id: adapter
        onBackendEvent: root.backendEvent()
        onMutationFinished: (operationId, success, code, message, retryable) => {
            if (operationId !== root.operation.id || !root.busy) return;
            if (!success) root.fail(code, message, retryable);
            else {
                root.mutationAccepted = true;
                if (root.operation.kind === "connect") root.refreshDetails(root.operation.target.device);
                root.observe();
            }
        }
    }
    Connections {
        target: root.operationDevice
        function onConnectedChanged() { root.observe(); adapter.refreshDetails(root.operation.target.device); }
        function onStateChanged() { root.observe(); }
    }
    Connections {
        target: root.observedNetwork
        function onConnectedChanged() { root.observe(); }
        function onStateChanged() { root.observe(); }
        function onConnectionFailed(reason) {
            if (!root.busy || root.operation.kind !== "connect") return;
            root.rawError = ConnectionFailReason.toString(reason);
            if (reason === ConnectionFailReason.NoSecrets)
                root.fail(root.passwordProvided ? "authentication-failed" : "password-required", root.passwordProvided ? qsTr("La contraseña no fue aceptada") : qsTr("Introduce la contraseña de esta red"), true);
            else if (reason === ConnectionFailReason.WifiAuthTimeout)
                root.fail("authentication-timeout", qsTr("La autenticación tardó demasiado"), true);
            else if (reason === ConnectionFailReason.WifiNetworkLost)
                root.fail("ap-unavailable", qsTr("La red ya no está disponible"), true);
            else root.fail("connection-failed", qsTr("No se pudo conectar a esta red"), true);
        }
    }
    Timer {
        id: deadline
        interval: 35000
        onTriggered: root.fail("timeout", qsTr("La operación tardó demasiado; comprueba el estado de la conexión"), true)
    }
    Timer {
        id: scanDeadline
        interval: 8000
        onTriggered: { root.setScanOwner("explicit-refresh", false); adapter.refresh(); }
    }
    Component.onCompleted: {
        syncScanners();
        if (wifiDevice) adapter.refreshDetails(wifiDevice.name);
    }
    Component.onDestruction: { for (const device of wifiDevices) device.scannerEnabled = false; }
}
