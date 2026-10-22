// One coordinator per graphical session, owned by the shell rather than a
// monitor. Automation requires explicit domain consent through fixed argv.
import QtQuick
import Quickshell
import Quickshell.Io
import "CortetsuPolicyModel.js" as Model

Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string sessionId: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property bool sessionAvailable: Model.validSession(sessionId, runtimeDir)
    readonly property string descriptorPath: `${runtimeDir}/cortetsu/bridge-${sessionId}.json`
    property var descriptor: null
    property bool negotiated: false
    property var capabilities: []
    property var snapshot: ({})
    property var rules: []
    property bool rulesLoaded: false
    property var explanation: []
    property var readQueue: []
    property int requestCounter: 0
    property string pendingRequest: ""
    property string pendingOperation: ""
    property string connectionState: "UNAVAILABLE"
    property string readError: ""
    property string lastError: ""
    property string actionErrorDomain: ""
    property var pendingAction: null
    property string commandOutput: ""
    property string commandError: ""
    property bool stopping: false
    property bool started: false
    property int reconnectAttempts: 0
    property int daemonAttempts: 0
    readonly property bool usable: negotiated && bridgeSocket.connected
    readonly property bool canChange: usable && snapshot.mode === "coordinator" && pendingAction === null
    readonly property string pendingDomain: pendingAction?.domain || ""
    readonly property string statusText: connectionState === "READY" ? qsTr("Conectado")
        : connectionState === "STALE" ? qsTr("Esperando datos de la sesión")
        : connectionState === "OBSERVING" ? qsTr("Esperando al escritorio")
        : connectionState === "CONNECTING" || connectionState === "NEGOTIATING" ? qsTr("Conectando")
        : connectionState === "TIMEOUT" ? qsTr("Sin respuesta; reconectando")
        : connectionState === "INCOMPATIBLE" || connectionState === "INVALID_RESPONSE" ? qsTr("Respuesta incompatible")
        : qsTr("No disponible; reintentando")

    function activation(domain: string): var { return Model.activation(snapshot, domain); }
    function ownedByAnother(domain: string): bool { return Model.ownedByAnother(snapshot, domain, sessionId); }

    function nextRequestId(): string {
        requestCounter = (requestCounter % 999999999) + 1;
        return `00000000-0000-4000-8000-${String(requestCounter).padStart(12, "0")}`;
    }
    function sendFrame(message: var): void {
        if (!bridgeSocket.connected) return;
        bridgeSocket.write(JSON.stringify(message) + "\n");
        bridgeSocket.flush();
    }
    function queueRead(operation: string, argument: string): void {
        if (!usable || !descriptor) return;
        if (pendingOperation === operation || readQueue.some(item => item.operation === operation)) return;
        if (operation === "policy.list" && !capabilities.includes("policy.observe")) return;
        if (operation === "explain.get" && !capabilities.includes("explain")) return;
        readQueue = [...readQueue, {operation: operation, argument: argument}];
        pumpRead();
    }
    function pumpRead(): void {
        if (!usable || pendingRequest || readQueue.length === 0) return;
        const item = readQueue[0];
        readQueue = readQueue.slice(1);
        const id = nextRequestId();
        const message = Model.readRequest(item.operation, id, descriptor, item.argument);
        if (!message) { Qt.callLater(pumpRead); return; }
        pendingRequest = id;
        pendingOperation = item.operation;
        sendFrame(message);
        requestDeadline.restart();
    }
    function requestSnapshot(): void { queueRead("snapshot.get", ""); }
    function requestPolicies(): void { queueRead("policy.list", ""); }
    function requestExplanation(traceId: string): void { queueRead("explain.get", traceId); }
    function refreshStatus(): void {
        if (usable) { requestSnapshot(); requestPolicies(); return; }
        reconnectAttempts = 0;
        reconnectTimer.stop();
        metadataFile.reload();
        scheduleReconnect();
        if (!coordinator.running) { daemonAttempts = 0; daemonRestart.stop(); recoverDaemon(); }
    }

    function sendHello(): void {
        if (!bridgeSocket.connected || !descriptor) return;
        negotiated = false;
        connectionState = "NEGOTIATING";
        sendFrame({type: "hello", protocol: "cortetsu.ipc", version: {major: 1, minor: 0},
            client: "cortetsu-shell", client_version: "2.0", session_id: descriptor.session_id,
            session_epoch: descriptor.session_epoch, capabilities: ["snapshot", "policy.observe", "explain"]});
        requestDeadline.restart();
    }
    function scheduleReconnect(): void {
        if (stopping || !started || !sessionAvailable || reconnectTimer.running) return;
        reconnectTimer.interval = Math.min(30000, 500 * Math.pow(2, Math.min(reconnectAttempts, 6)));
        reconnectAttempts++;
        reconnectTimer.restart();
    }
    function failConnection(state: string): void {
        negotiated = false;
        capabilities = [];
        pendingRequest = "";
        pendingOperation = "";
        readQueue = [];
        snapshot = ({});
        rulesLoaded = false;
        requestDeadline.stop();
        connectionState = state;
        scheduleReconnect();
        bridgeSocket.connected = false;
    }
    function acceptDescriptor(raw: string): void {
        let info;
        try { info = JSON.parse(raw); } catch (_) { info = null; }
        if (!Model.validDescriptor(info, root.sessionId, root.runtimeDir)) {
            descriptor = null;
            failConnection("UNAVAILABLE");
            return;
        }
        const changed = !descriptor || descriptor.socket !== info.socket || descriptor.session_epoch !== info.session_epoch;
        descriptor = info;
        if (changed) {
            reconnectAttempts = 0;
            failConnection("CONNECTING");
        } else if (!bridgeSocket.connected) scheduleReconnect();
    }
    function acceptFrame(line: string): void {
        if (line.length > 65536 || Model.utf8Length(line) > 65536) { failConnection("INVALID_RESPONSE"); return; }
        let message;
        try { message = JSON.parse(line); } catch (_) { failConnection("INVALID_RESPONSE"); return; }
        if (!Model.protocol(message)) { failConnection("INCOMPATIBLE"); return; }
        if (message.type === "hello_ack") {
            if (negotiated || !Model.validHello(message, descriptor)) { failConnection("INCOMPATIBLE"); return; }
            requestDeadline.stop();
            negotiated = true;
            capabilities = message.capabilities;
            reconnectAttempts = 0;
            reconnectTimer.stop();
            connectionState = "CONNECTED";
            requestSnapshot();
            requestPolicies();
            return;
        }
        if (!negotiated || !Model.matchingResponse(message, pendingRequest)) return;
        const operation = pendingOperation;
        pendingRequest = "";
        pendingOperation = "";
        requestDeadline.stop();
        if (message.outcome !== "read") {
            readError = qsTr("No se pudo consultar el coordinador");
            if (operation === "snapshot.get") { failConnection("OWNER_UNAVAILABLE"); return; }
        } else if (operation === "snapshot.get") {
            const value = Model.normaliseSnapshot(message.body);
            if (value === null) { failConnection("INVALID_RESPONSE"); return; }
            snapshot = value;
            readError = "";
            connectionState = value.stream_stale ? "STALE" : value.authoritative ? "READY" : "OBSERVING";
            if (pendingAction?.phase === "readback" && Model.actionConfirmed(pendingAction, snapshot)) {
                pendingAction = null;
                actionDeadline.stop();
                lastError = "";
                actionErrorDomain = "";
            }
        } else if (operation === "policy.list") {
            if (Array.isArray(message.body?.rules) && message.body.rules.length <= 128) { rules = message.body.rules; rulesLoaded = true; }
            else readError = qsTr("El catálogo de reglas no es válido");
        } else if (operation === "explain.get") {
            const values = Model.decisions(message.body?.decisions);
            if (values !== null) explanation = values;
            else readError = qsTr("La explicación no está disponible");
        }
        pumpRead();
    }

    function change(operation: string, domain: string, argument: var): void {
        const command = Model.commandFor(operation, domain, argument);
        if (!command || !canChange) return;
        if (operation === "revoke") {
            if (!ownedByAnother(domain) || activation(domain).owner_session !== argument) return;
        } else if (ownedByAnother(domain)) return;
        lastError = "";
        actionErrorDomain = "";
        commandOutput = "";
        commandError = "";
        pendingAction = {operation: operation, domain: domain, seconds: operation === "override" ? argument : 0,
            expectedOwner: operation === "revoke" ? argument : "", session: sessionId, phase: "command"};
        policyCommand.command = command;
        policyCommand.running = true;
        actionDeadline.restart();
    }
    function setDomainEnabled(domain: string, enabled: bool): void { change(enabled ? "enable" : "disable", domain, 0); }
    function overrideDomain(domain: string, seconds: int): void { change("override", domain, seconds); }
    function revokeDomain(domain: string, expectedOwner: string): void { change("revoke", domain, expectedOwner); }
    function failAction(message: string): void {
        actionErrorDomain = pendingAction?.domain || "";
        pendingAction = null;
        actionDeadline.stop();
        lastError = message;
        requestSnapshot();
    }
    function finishAction(exitCode: int): void {
        if (stopping || pendingAction?.phase !== "command") return;
        let reply;
        try { reply = commandOutput.length <= 65536 ? JSON.parse(commandOutput) : null; } catch (_) { reply = null; }
        if (exitCode !== 0 || !Model.commandAccepted(pendingAction, reply)) {
            failAction(commandError.includes("SESSION_MISMATCH") ? qsTr("La autorización cambió en otra sesión; consulta su estado antes de reintentar")
                : qsTr("No se pudo confirmar el cambio; consulta el estado antes de reintentar"));
            return;
        }
        pendingAction = Object.assign({}, pendingAction, {phase: "readback", until: reply.manual_override_until_unix_ms});
        requestSnapshot();
    }
    function recoverDaemon(): void {
        daemonHealthy.stop();
        if (stopping || !started || usable || daemonRestart.running) return;
        daemonRestart.interval = Math.min(30000, 1000 * Math.pow(2, Math.min(daemonAttempts, 5)));
        daemonAttempts++;
        daemonRestart.restart();
    }

    FileView {
        id: metadataFile
        path: root.sessionAvailable ? root.descriptorPath : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.acceptDescriptor(text())
        onFileChanged: reload()
        onLoadFailed: { root.descriptor = null; root.failConnection("UNAVAILABLE"); }
    }
    Socket {
        id: bridgeSocket
        path: root.descriptor?.socket || ""
        connected: false
        onConnectedChanged: {
            if (connected) root.sendHello();
            else if (!root.stopping) { root.failConnection("DISCONNECTED"); if (!coordinator.running) root.recoverDaemon(); }
        }
        onError: error => root.failConnection("UNAVAILABLE")
        parser: SplitParser { onRead: line => root.acceptFrame(line) }
    }
    Timer {
        id: reconnectTimer
        onTriggered: {
            if (root.stopping) return;
            metadataFile.reload();
            if (root.descriptor && !bridgeSocket.connected) bridgeSocket.connected = true;
        }
    }
    Timer {
        interval: 5000
        repeat: true
        running: root.started && !root.stopping && root.descriptor === null && root.sessionAvailable
        onTriggered: metadataFile.reload()
    }
    Timer { id: requestDeadline; interval: 6000; onTriggered: root.failConnection("TIMEOUT") }
    Timer {
        interval: 20000
        repeat: true
        running: root.usable
        onTriggered: root.requestSnapshot()
    }
    Timer {
        interval: 500
        repeat: true
        running: root.pendingAction?.phase === "readback"
        onTriggered: root.requestSnapshot()
    }
    Timer {
        id: actionDeadline
        interval: 12000
        onTriggered: {
            if (policyCommand.running) policyCommand.signal(9);
            root.failAction(qsTr("El cambio no se ha confirmado a tiempo; vuelve a consultar el estado"));
        }
    }
    // startup inventory: cortetsu:policy-command
    Process {
        id: policyCommand
        environment: ({HYPRLAND_INSTANCE_SIGNATURE: root.sessionId})
        stdout: StdioCollector { onStreamFinished: root.commandOutput = text }
        stderr: StdioCollector { onStreamFinished: root.commandError = text }
        onExited: exitCode => root.finishAction(exitCode)
        onRunningChanged: if (!running) Qt.callLater(() => { if (root.pendingAction?.phase === "command") root.finishAction(127); })
    }
    // startup inventory: cortetsu:coordinator
    Process {
        id: coordinator
        command: ["cortetsu-coordinator", "--observe"]
        environment: ({HYPRLAND_INSTANCE_SIGNATURE: root.sessionId})
        onStarted: daemonHealthy.restart()
        onExited: () => root.recoverDaemon()
        onRunningChanged: if (!running) Qt.callLater(root.recoverDaemon)
    }
    Timer { id: daemonHealthy; interval: 30000; onTriggered: root.daemonAttempts = 0 }
    Timer {
        id: daemonRestart
        onTriggered: if (!root.stopping && root.sessionAvailable && !root.usable) coordinator.running = true
    }
    IpcHandler {
        target: "cortetsu-v2-bridge"
        function inspect(): string {
            return JSON.stringify({state: root.connectionState, connected: root.usable, snapshot: root.snapshot,
                pending: root.pendingDomain, last_error: root.lastError});
        }
        function refresh(): void { root.requestSnapshot(); }
    }
    Component.onCompleted: {
        started = true;
        if (sessionAvailable) { coordinator.running = true; scheduleReconnect(); }
    }
    Component.onDestruction: {
        stopping = true;
        reconnectTimer.stop(); daemonRestart.stop(); requestDeadline.stop(); actionDeadline.stop(); daemonHealthy.stop();
        bridgeSocket.connected = false;
        coordinator.running = false;
        policyCommand.running = false;
    }
}
