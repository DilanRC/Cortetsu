pragma Singleton
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "BluetoothPolicy.js" as Policy

Singleton {
    id: root
    readonly property var adapters: Bluetooth.adapters.values
    property BluetoothAdapter selectedAdapter: null
    readonly property BluetoothAdapter adapter: Policy.contains(adapters, selectedAdapter)
        ? selectedAdapter : (Policy.contains(adapters, Bluetooth.defaultAdapter) ? Bluetooth.defaultAdapter : (adapters[0] ?? null))
    readonly property var devices: adapter ? adapter.devices.values : []
    readonly property var allDevices: Bluetooth.devices.values
    property var confirmedPower: ({})
    property var confirmedProperties: ({})
    readonly property bool enabled: adapter ? (confirmedPower[adapter.dbusPath] ?? adapter.enabled) : false
    readonly property int connectedCount: allDevices.filter(d => d.connected).length
    readonly property string state: !adapter ? "unavailable" : BluetoothAdapterState.toString(adapter.state).toLowerCase()
    readonly property bool discovering: adapter?.discovering ?? false
    readonly property bool authenticationSupported: false
    readonly property string authenticationNotice: qsTr("El emparejamiento que solicita PIN o confirmación requiere un agente Bluetooth del sistema; esta versión de Quickshell no expone esas solicitudes.")
    property var operation: ({id: 0, kind: "", state: "idle", target: null, startedAt: 0,
        lastError: "", lastErrorCode: "", retryable: false})
    property var scanOwners: ({})
    property BluetoothAdapter scanningAdapter: null
    property var acquiredAdapters: []
    property var operationAdapter: null
    property var operationTarget: null
    property bool operationExpected: false
    property int serial: 0
    property bool dispatching: false
    readonly property bool busy: operation.state === "pending"
    // Read native properties in the binding so completion follows BlueZ notifications.
    readonly property var observed: busy ? [adapters.length, devices.length, operationTarget?.enabled,
        operationTarget?.connected, operationTarget?.paired, operationTarget?.bonded,
        operationTarget?.pairing, operationTarget?.trusted, operationTarget?.blocked] : []
    onObservedChanged: Qt.callLater(checkCompletion)
    onAdapterChanged: { reconcileScan(); reconcilePower(); Qt.callLater(checkCompletion); }
    onEnabledChanged: reconcileScan()
    onAdaptersChanged: {
        const present = adapters.map(item => item.dbusPath);
        const next = {};
        for (const path of Object.keys(confirmedPower ?? {})) if (present.includes(path)) next[path] = confirmedPower[path];
        confirmedPower = next;
        reconcilePower();
        Qt.callLater(checkCompletion);
    }
    onAllDevicesChanged: {
        const present = allDevices.map(item => item.dbusPath);
        const next = {};
        for (const key of Object.keys(confirmedProperties ?? {}))
            if (present.some(path => key.startsWith(path + ":"))) next[key] = confirmedProperties[key];
        confirmedProperties = next;
    }
    onDevicesChanged: Qt.callLater(checkCompletion)

    function propertyValue(device, property) {
        if (!device) return false;
        return confirmedProperties[device.dbusPath + ":" + property] ?? device[property];
    }
    function confirmProperty(device, property, value) {
        const next = Object.assign({}, confirmedProperties);
        next[device.dbusPath + ":" + property] = value;
        confirmedProperties = next;
    }
    function propertyChanged(device, property) {
        if (busy && operationTarget === device && (operation.kind === property || operation.kind === "wake" && property === "wakeAllowed")) return;
        confirmProperty(device, property, device[property]);
    }
    function selectAdapter(value) {
        if (busy || !Policy.contains(adapters, value)) return false;
        selectedAdapter = value;
        return true;
    }
    function setScanOwner(owner, active) {
        if (!owner) return;
        const next = Object.assign({}, scanOwners);
        if (active) next[owner] = true; else delete next[owner];
        scanOwners = next;
        reconcileScan();
    }
    function reconcileScan() {
        const wanted = enabled && Object.keys(scanOwners).length > 0 ? adapter : null;
        if (scanningAdapter !== wanted) {
            if (Policy.contains(adapters, scanningAdapter)) scanningAdapter.discovering = false;
            scanningAdapter = wanted;
        }
        if (scanningAdapter && !scanningAdapter.discovering) {
            if (acquiredAdapters.indexOf(scanningAdapter) === -1) acquiredAdapters = [...acquiredAdapters, scanningAdapter];
            scanningAdapter.discovering = true;
        }
    }
    function finish(status, code, message) {
        deadline.stop();
        verificationTick.stop();
        verification.running = false;
        operation = Object.assign({}, operation, {state: status, lastErrorCode: code ?? "",
            lastError: message ?? "", retryable: status === "failed"});
        operationTarget = null;
    }
    function checkCompletion() {
        if (!busy || dispatching) return;
        if (!Policy.contains(adapters, operationAdapter)) {
            finish("failed", "adapter-removed", qsTr("El adaptador ya no está disponible."));
            return;
        }
        const members = ["power", "discoverable", "pairable"].indexOf(operation.kind) !== -1 ? adapters : devices;
        if (operation.kind !== "forget" && !Policy.contains(members, operationTarget)) {
            finish("failed", "target-removed", qsTr("El dispositivo ya no está disponible."));
            return;
        }
        if (["power", "trusted", "blocked", "discoverable", "pairable", "wake"].indexOf(operation.kind) !== -1) return;
        const result = Policy.completion(operation.kind, operationTarget, operationExpected, members);
        if (result === "removed") finish("failed", "target-removed", qsTr("El dispositivo ya no está disponible en el adaptador seleccionado."));
        else if (result) finish("succeeded");
    }
    function start(kind, target, expected) {
        if (busy) return false;
        const members = ["power", "discoverable", "pairable"].indexOf(kind) !== -1 ? adapters : devices;
        if (!Policy.contains(members, target)) return false;
        if (kind !== "power" && !enabled) return false;
        if (kind === "power") {
            const power = Object.assign({}, confirmedPower);
            power[target.dbusPath] = enabled;
            confirmedPower = power;
        }
        if (["trusted", "blocked", "wake"].includes(kind)) {
            const property = kind === "wake" ? "wakeAllowed" : kind;
            confirmProperty(target, property, propertyValue(target, property));
        }
        dispatching = true;
        operationExpected = !!expected;
        operationTarget = target;
        operationAdapter = kind === "power" || kind === "discoverable" || kind === "pairable" ? target : adapter;
        operation = {id: ++serial, kind: kind, state: "pending", target: target,
            startedAt: Date.now(), lastError: "", lastErrorCode: "", retryable: false};
        deadline.interval = kind === "pair" ? 60000 : 20000;
        deadline.start();
        try {
            if (kind === "power") {
                // A stale native value equal to the request would skip the D-Bus write.
                if (target.enabled === expected) {
                    powerWrite.command = ["busctl", "--system", "--timeout=5", "set-property", "org.bluez", target.dbusPath,
                        "org.bluez.Adapter1", "Powered", "b", expected ? "true" : "false"];
                    powerWrite.running = true;
                } else target.enabled = expected;
            }
            else if (kind === "discoverable") target.discoverable = expected;
            else if (kind === "pairable") target.pairable = expected;
            else if (kind === "wake") target.wakeAllowed = expected;
            else if (kind === "trusted") target.trusted = expected;
            else if (kind === "blocked") target.blocked = expected;
            else if (kind === "connect") target.connect();
            else if (kind === "disconnect") target.disconnect();
            else if (kind === "pair") target.pair();
            else if (kind === "cancel-pair") target.cancelPair();
            else if (kind === "forget") target.forget();
        } catch (error) { finish("failed", "native-call", String(error)); }
        dispatching = false;
        if (["power", "trusted", "blocked", "discoverable", "pairable", "wake"].indexOf(kind) !== -1 && busy) verificationTick.start();
        checkCompletion();
        return true;
    }
    function setEnabled(value) { return start("power", adapter, value); }
    function setDiscoverable(value) { return start("discoverable", adapter, value); }
    function setPairable(value) { return start("pairable", adapter, value); }
    function connectDevice(device) { return start("connect", device); }
    function disconnectDevice(device) { return start("disconnect", device); }
    function pairDevice(device) { return start("pair", device); }
    function forgetDevice(device) { return start("forget", device); }
    function setTrusted(device, value) { return start("trusted", device, value); }
    function setWakeAllowed(device, value) { return start("wake", device, value); }
    function setBlocked(device, value) { return start("blocked", device, value); }
    function cancelPair() {
        if (busy && operation.kind === "pair") {
            const device = operationTarget;
            finish("cancelled");
            return start("cancel-pair", device);
        }
        return false;
    }
    Instantiator {
        model: root.adapters
        delegate: Connections {
            required property var modelData
            target: modelData
            function onDiscoveringChanged() {
                if (modelData.discovering && root.acquiredAdapters.indexOf(modelData) !== -1
                    && (root.scanningAdapter !== modelData || !root.enabled || Object.keys(root.scanOwners).length === 0))
                    modelData.discovering = false;
            }
        }
    }
    Instantiator {
        model: root.allDevices
        delegate: Connections {
            required property var modelData
            target: modelData
            function onTrustedChanged() { root.propertyChanged(modelData, "trusted"); }
            function onBlockedChanged() { root.propertyChanged(modelData, "blocked"); }
            function onWakeAllowedChanged() { root.propertyChanged(modelData, "wakeAllowed"); }
        }
    }
    Connections {
        target: root.adapter
        function onEnabledChanged() {
            if (root.busy && root.operation.kind === "power") return;
            if (root.adapter) {
                const power = Object.assign({}, root.confirmedPower);
                power[root.adapter.dbusPath] = root.adapter.enabled;
                root.confirmedPower = power;
            }
        }
    }
    // Native setters cache desired values before their DBus write completes.
    // Verify those writes against BlueZ only while an operation is pending.
    Timer {
        id: verificationTick
        interval: 500
        repeat: true
        onTriggered: {
            if (!root.busy || verification.running) return;
            const kind = root.operation.kind;
            const property = kind === "power" ? "Powered" : kind === "trusted" ? "Trusted" : kind === "discoverable" ? "Discoverable" : kind === "pairable" ? "Pairable" : kind === "wake" ? "WakeAllowed" : "Blocked";
            verification.command = ["busctl", "--system", "--timeout=2", "get-property", "org.bluez", root.operation.target.dbusPath,
                ["power", "discoverable", "pairable"].indexOf(kind) !== -1 ? "org.bluez.Adapter1" : "org.bluez.Device1", property];
            verification.operationId = root.operation.id;
            verification.running = true;
        }
    }
    Process {
        id: verification
        property int operationId: 0
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.busy && verification.operationId === root.operation.id
                    && text.trim() === "b " + (root.operationExpected ? "true" : "false")) {
                    if (root.operation.kind === "power") {
                        const power = Object.assign({}, root.confirmedPower);
                        power[root.operation.target.dbusPath] = root.operationExpected;
                        root.confirmedPower = power;
                    }
                    if (["trusted", "blocked", "wake"].includes(root.operation.kind))
                        root.confirmProperty(root.operation.target, root.operation.kind === "wake" ? "wakeAllowed" : root.operation.kind, root.operationExpected);
                    root.finish("succeeded");
                }
            }
        }
    }
    // Quickshell can keep a re-registered adapter (after resume) cached as off while BlueZ has it on.
    // Read BlueZ until its power state settles: a bounded readback per adapter change, no idle polling.
    property int powerReads: 0
    function reconcilePower() {
        powerReads = 0;
        if (adapter) powerSettle.restart();
    }
    Timer {
        id: powerSettle
        interval: 2000
        onTriggered: {
            if (!root.adapter || powerReadback.running) return;
            powerReadback.path = root.adapter.dbusPath;
            powerReadback.command = ["busctl", "--system", "--timeout=2", "get-property", "org.bluez", powerReadback.path, "org.bluez.Adapter1", "PowerState"];
            powerReadback.running = true;
        }
    }
    Process {
        id: powerReadback
        property string path: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const value = text.trim();
                const settled = /^s "[a-z-]+"$/.test(value) && !/-(enabling|disabling)"$/.test(value);
                if (!settled) {
                    if (++root.powerReads < 8) powerSettle.restart();
                    return;
                }
                if (root.adapter?.dbusPath !== powerReadback.path || (root.busy && root.operation.kind === "power")) return;
                const power = Object.assign({}, root.confirmedPower);
                power[powerReadback.path] = value === 's "on"';
                root.confirmedPower = power;
            }
        }
    }
    Process { id: powerWrite }
    Component.onCompleted: reconcilePower()
    Timer {
        id: deadline
        onTriggered: {
            if (!root.busy) return;
            if (root.operation.kind === "pair" && Policy.contains(root.devices, root.operationTarget)) root.operationTarget.cancelPair();
            root.finish("failed", "timeout", qsTr("BlueZ no confirmó la operación a tiempo. Comprueba el dispositivo y vuelve a intentar."));
        }
    }
    Component.onDestruction: {
        for (const owned of acquiredAdapters) if (Policy.contains(adapters, owned)) owned.discovering = false;
    }
}
