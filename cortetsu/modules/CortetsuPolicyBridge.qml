// Cortetsu 2.0 read-only IPC client, opt-in only.
// Not a window: one instance per shell, independent of monitor count.
// Safe if the optional Go bridge is absent: no focus, grabs or mutations.
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    visible: false
    width: 0
    height: 0

    readonly property string sessionId: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
    readonly property string descriptorPath: `${runtimeDir}/cortetsu/bridge-${sessionId}.json`
    property var descriptor: null
    property bool negotiated: false
    property var snapshot: ({})
    property int requestCounter: 0
    property string pendingRequest: ""
    property string connectionState: "UNAVAILABLE"
    readonly property bool usable: negotiated && bridgeSocket.connected

    // Requests only harmless snapshots. Sequence-based read IDs are not a
    // credential and cannot be used as idempotency keys for mutations.
    function nextRequestId(): string {
        requestCounter = (requestCounter % 999999999) + 1;
        return `00000000-0000-4000-8000-${String(requestCounter).padStart(12, "0")}`;
    }

    function sendFrame(message: var): void {
        if (!bridgeSocket.connected)
            return;
        bridgeSocket.write(JSON.stringify(message) + "\n");
        bridgeSocket.flush();
    }

    function requestSnapshot(): void {
        if (!negotiated || !bridgeSocket.connected || !descriptor)
            return;
        pendingRequest = nextRequestId();
        sendFrame({
            type: "request", protocol: "cortetsu.ipc",
            version: { major: 1, minor: 0 },
            id: pendingRequest, op: "snapshot.get",
            session_id: descriptor.session_id,
            session_epoch: descriptor.session_epoch,
            deadline_ms: 5000,
            body: { domains: ["coordinator"] }
        });
    }

    function sendHello(): void {
        if (!bridgeSocket.connected || !descriptor)
            return;
        negotiated = false;
        connectionState = "NEGOTIATING";
        sendFrame({
            type: "hello", protocol: "cortetsu.ipc",
            version: { major: 1, minor: 0 },
            client: "cortetsu-shell", client_version: "2.0",
            session_id: descriptor.session_id,
            session_epoch: descriptor.session_epoch,
            capabilities: ["snapshot"]
        });
    }

    function acceptFrame(line: string): void {
        if (line.length > 65536) {
            connectionState = "REJECTED";
            descriptor = null;
            return;
        }
        let message;
        try { message = JSON.parse(line); }
        catch (_) { connectionState = "INVALID_RESPONSE"; return; }
        if (!message || message.protocol !== "cortetsu.ipc" ||
            (message.type === "hello_ack" || message.type === "response") &&
            (message.version?.major !== 1 || message.version?.minor !== 0 ||
             (message.type === "hello_ack" &&
              (message.session_id !== descriptor?.session_id || message.session_epoch !== descriptor?.session_epoch)))) {
            connectionState = "INCOMPATIBLE";
            negotiated = false;
            return;
        }
        if (message.type === "hello_ack") {
            if (!Array.isArray(message.capabilities) || message.capabilities.indexOf("snapshot") < 0) {
                connectionState = "UNSUPPORTED_CAPABILITY";
                return;
            }
            negotiated = true;
            connectionState = "CONNECTED";
            requestSnapshot();
        } else if (message.type === "response" && negotiated && message.id === pendingRequest) {
            pendingRequest = "";
            if (message.outcome === "read" && message.body &&
                message.body.mode === "observe" && typeof message.body.authoritative === "boolean" &&
                typeof message.body.stream_stale === "boolean") {
                snapshot = message.body;
                connectionState = message.body.stream_stale ? "STALE" : message.body.authoritative ? "READY" : "OBSERVING";
            } else {
                connectionState = "OWNER_UNAVAILABLE";
            }
        }
    }

    FileView {
        id: metadataFile
        path: root.descriptorPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const info = JSON.parse(text());
                if (info.protocol !== "cortetsu.ipc" ||
                    info.session_id !== root.sessionId ||
                    typeof info.session_epoch !== "number" || info.session_epoch <= 0 ||
                    typeof info.socket !== "string" ||
                    info.socket !== `${root.runtimeDir}/cortetsu/cortetsu-${root.sessionId}.sock`)
                    throw new Error("invalid bridge descriptor");
                root.descriptor = info;
            } catch (_) {
                root.descriptor = null;
                root.connectionState = "UNAVAILABLE";
            }
        }
        onFileChanged: reload()
        onLoadFailed: {
            root.descriptor = null;
            root.connectionState = "UNAVAILABLE";
        }
    }

    // The optional client is never started or polled when its Loader is off.
    Timer {
        interval: 2500
        repeat: true
        running: root.descriptor === null
        onTriggered: metadataFile.reload()
    }

    Socket {
        id: bridgeSocket
        path: root.descriptor?.socket || ""
        connected: root.descriptor !== null && path !== ""
        onConnectedChanged: {
            if (connected) root.sendHello();
            else {
                root.negotiated = false;
                root.connectionState = "DISCONNECTED";
            }
        }
        onError: error => { root.connectionState = "UNAVAILABLE"; }
        parser: SplitParser {
            onRead: line => root.acceptFrame(line)
        }
    }

    // Read-only heartbeat keeps the server's bounded session alive. It does
    // not poll GPU, network or hardware APIs and never writes user state.
    Timer {
        interval: 20000
        repeat: true
        running: root.usable
        onTriggered: root.requestSnapshot()
    }

    IpcHandler {
        target: "cortetsu-v2-bridge"
        function inspect(): string {
            return JSON.stringify({ state: root.connectionState, connected: root.usable,
                                    snapshot: root.snapshot });
        }
        function refresh(): void { root.requestSnapshot(); }
    }
}
