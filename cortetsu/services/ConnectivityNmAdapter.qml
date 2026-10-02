import QtQuick
import Quickshell.Io
import "ConnectivityPolicy.js" as Policy

QtObject {
    id: root
    property list<var> profiles: []
    property list<var> accessPoints: []
    property var details: ({})
    property string detailsState: "idle"
    property string lastError: ""
    property string rawError: ""
    property var queue: []
    property var job: null
    property string output: ""
    property string errorOutput: ""
    property bool profilesReady: false
    property bool radioReady: false
    property bool radioEnabled: false
    property bool stopping: false
    property int monitorAttempts: 0
    property bool profileEventPending: false
    property int profileGeneration: 0
    property bool commandTimedOut: false
    readonly property bool busy: worker.running
    readonly property bool profileReadsPending: ["profiles", "profile"].includes(job?.kind)
        || queue.some(item => ["profiles", "profile"].includes(item.kind))
    signal backendEvent()
    signal hiddenProfileCreated(int operationId)
    signal operationCancelled(int operationId)
    signal mutationFinished(int operationId, bool success, string code, string message, bool retryable)

    function enqueue(kind, args, context) {
        if (queue.some(item => item.kind === kind && JSON.stringify(item.context) === JSON.stringify(context))) return;
        const item = { kind: kind, args: args, context: context || {} };
        queue = kind === "mutation" ? [item, ...queue] : [...queue, item];
        pump();
    }
    function pump() {
        if (worker.running || job || queue.length === 0) return;
        job = queue[0];
        queue = queue.slice(1);
        output = ""; errorOutput = ""; commandTimedOut = false;
        worker.stdinEnabled = !!job.context.usesStdin;
        worker.command = ["nmcli", "--wait", "12", "-t", "--escape", "yes", ...job.args];
        worker.running = true;
        commandDeadline.restart();
    }
    function refresh() {
        refreshRadio();
        refreshProfiles(true);
        enqueue("aps", ["-f", "IN-USE,BSSID,SSID,SIGNAL,FREQ,SECURITY,DEVICE", "device", "wifi", "list", "--rescan", "no"], {});
    }
    function refreshRadio() {
        enqueue("radio", ["radio", "wifi"], {});
    }
    function refreshProfiles(includeMetadata) {
        enqueue("profiles", ["-f", "UUID,NAME,TYPE,AUTOCONNECT,DEVICE", "connection", "show"], { includeMetadata: !!includeMetadata });
    }
    function cancelOperation(operationId) {
        operationCancelled(operationId);
        queue = queue.filter(item => item.kind !== "mutation" || item.context.operationId !== operationId);
        if (job?.kind === "mutation" && job.context.operationId === operationId) {
            job.cancelled = true;
            worker.running = false;
        }
    }
    function monitorEvent(data) {
        backendEvent();
        if (/^connection\b/i.test(data)) profileEventPending = true;
        if (!debounce.running) debounce.start();
    }
    function refreshDetails(device) {
        if (!device) return;
        detailsState = "loading";
        enqueue("details", ["-f", "GENERAL.DEVICE,GENERAL.CON-UUID,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,IP6.ADDRESS,IP6.GATEWAY,IP6.DNS", "device", "show", device], { device: device });
    }
    function activateWithPassword(operationId, uuid, device, password) {
        if (!Policy.validUuid(uuid) || !password || /[\r\n\0]/.test(password)) {
            mutationFinished(operationId, false, "invalid-password", "Comprueba la contraseña", false); return;
        }
        let secret = password;
        function release() {
            secret = "";
            root.operationCancelled.disconnect(cancelled);
            worker.started.disconnect(send);
        }
        function cancelled(id) { if (id === operationId) release(); }
        function send() {
            if (root.job?.context?.operationId !== operationId || !root.job.context.usesStdin) return;
            worker.write("802-11-wireless-security.psk:" + secret + "\n");
            worker.stdinEnabled = false;
            release();
        }
        root.operationCancelled.connect(cancelled);
        worker.started.connect(send);
        enqueue("mutation", ["connection", "up", "uuid", uuid, ...(device ? ["ifname", device] : []), "passwd-file", "/dev/stdin"],
            { operationId: operationId, kind: "connect", usesStdin: true });
    }
    function createHidden(operationId, uuid, ssid, device, security, password) {
        let secret = password;
        function release() {
            secret = "";
            root.hiddenProfileCreated.disconnect(afterCreate);
            root.operationCancelled.disconnect(cancelled);
        }
        function cancelled(id) { if (id === operationId) release(); }
        function afterCreate(id) {
            if (id !== operationId) return;
            if (security === "open") root.mutate(operationId, "connect", uuid, false, device);
            else root.activateWithPassword(operationId, uuid, device, secret);
            release();
        }
        root.hiddenProfileCreated.connect(afterCreate);
        root.operationCancelled.connect(cancelled);
        enqueue("mutation", ["connection", "add", "type", "wifi", "ifname", device,
            "con-name", ssid, "ssid", ssid, "connection.uuid", uuid, "802-11-wireless.hidden", "yes",
            ...(security === "open" ? [] : ["802-11-wireless-security.key-mgmt", security])],
            { operationId: operationId, kind: "create-hidden" });
    }
    function setIpv4(operationId, uuid, config) {
        if (!Policy.validUuid(uuid)) { mutationFinished(operationId, false, "profile-invalid", "El UUID del perfil no es válido", false); return; }
        enqueue("mutation", ["connection", "modify", "uuid", uuid, "ipv4.method", config.method,
            "ipv4.addresses", config.addresses.join(","), "ipv4.gateway", config.gateway,
            "ipv4.dns", config.dns.join(","), "ipv4.ignore-auto-dns", config.ignoreAutoDns ? "yes" : "no"], { operationId: operationId, kind: "ipv4" });
    }
    function mutate(operationId, kind, uuid, enabled, device) {
        if (!Policy.validUuid(uuid)) { mutationFinished(operationId, false, "profile-invalid", "El UUID del perfil no es válido", false); return; }
        const args = kind === "forget" ? ["connection", "delete", "uuid", uuid]
            : kind === "autoconnect" ? ["connection", "modify", "uuid", uuid, "connection.autoconnect", enabled ? "yes" : "no"]
            : ["connection", "up", "uuid", uuid, ...(device ? ["ifname", device] : [])];
        enqueue("mutation", args, { operationId: operationId, kind: kind });
    }
    function finish(exitCode) {
        commandDeadline.stop();
        const completed = job;
        job = null;
        if (!completed) return;
        if (completed.cancelled) { Qt.callLater(pump); return; }
        if (commandTimedOut || exitCode !== 0) {
            const error = commandTimedOut ? {code: "timeout", message: "NetworkManager tardó demasiado", retryable: true} : Policy.commandError(errorOutput, exitCode);
            rawError = errorOutput;
            lastError = error.message;
            if (completed.kind === "details") detailsState = "failed";
            if (completed.kind === "mutation") mutationFinished(completed.context.operationId, false, error.code, error.message, error.retryable);
        } else {
            lastError = "";
            if (completed.kind === "radio") { radioEnabled = output.trim() === "enabled"; radioReady = true; }
            else if (completed.kind === "aps") accessPoints = Policy.accessPoints(output);
            else if (completed.kind === "profiles") {
                const previous = profiles;
                profileGeneration++;
                profiles = Policy.profiles(output).map(profile => {
                    const old = previous.find(p => p.uuid === profile.uuid);
                    if (old) { profile.ssid = old.ssid; profile.interface = old.interface; profile.ipv4 = old.ipv4; profile.hidden = old.hidden; profile.security = old.security; }
                    return profile;
                });
                profilesReady = true;
                for (const profile of profiles)
                    if (completed.context.includeMetadata || !previous.some(old => old.uuid === profile.uuid && (old.type === "802-11-wireless" ? old.ssid.length > 0 : !!old.ipv4))) enqueue("profile", ["-f", "802-11-wireless.ssid,connection.interface-name,ipv4.method,ipv4.addresses,ipv4.gateway,ipv4.dns,ipv4.ignore-auto-dns,802-11-wireless.hidden,802-11-wireless-security.key-mgmt", "connection", "show", "uuid", profile.uuid], { uuid: profile.uuid, generation: profileGeneration });
            } else if (completed.kind === "profile" && completed.context.generation === profileGeneration) {
                const props = Policy.properties(output);
                profiles = profiles.map(profile => profile.uuid !== completed.context.uuid ? profile : Object.assign({}, profile, {
                    ssid: props["802-11-wireless.ssid"]?.[0] || "", interface: props["connection.interface-name"]?.[0] || "",
                    hidden: props["802-11-wireless.hidden"]?.[0] === "yes", security: props["802-11-wireless-security.key-mgmt"]?.[0] || "open",
                    ipv4: { method: props["ipv4.method"]?.[0] || "auto", addresses: Policy.ipList(props["ipv4.addresses"]?.[0]),
                        gateway: props["ipv4.gateway"]?.[0] || "", dns: Policy.ipList(props["ipv4.dns"]?.[0]), ignoreAutoDns: props["ipv4.ignore-auto-dns"]?.[0] === "yes" }
                }));
            } else if (completed.kind === "details") {
                const props = Policy.properties(output);
                const next = Object.assign({}, details);
                next[completed.context.device] = {
                    device: completed.context.device, uuid: props["GENERAL.CON-UUID"]?.[0] || "", profileName: props["GENERAL.CONNECTION"]?.[0] || "", profile: props["GENERAL.CONNECTION"]?.[0] || "",
                    address: (props["IP4.ADDRESS"]?.[0] || "").split("/")[0], addresses: props["IP4.ADDRESS"] || [],
                    gateway: props["IP4.GATEWAY"]?.[0] || "", dns: props["IP4.DNS"] || [],
                    ipv6Addresses: props["IP6.ADDRESS"] || [], ipv6: props["IP6.ADDRESS"] || [], ipv6Gateway: props["IP6.GATEWAY"]?.[0] || "", ipv6Dns: props["IP6.DNS"] || []
                };
                details = next; detailsState = "ready";
            } else if (completed.kind === "mutation") {
                if (completed.context.kind === "create-hidden") hiddenProfileCreated(completed.context.operationId);
                else mutationFinished(completed.context.operationId, true, "", "", false);
                refresh();
            }
        }
        Qt.callLater(pump);
    }
    // startup inventory: cortetsu:connectivity-command
    readonly property Process worker: Process {
        id: worker
        environment: ({ LC_ALL: "C", LANG: "C" })
        stdout: StdioCollector { onStreamFinished: root.output = text }
        stderr: StdioCollector { onStreamFinished: root.errorOutput = text }
        onExited: exitCode => root.finish(exitCode)
        onRunningChanged: if (!running && root.job && commandDeadline.running) root.finish(127)
    }
    readonly property Timer commandDeadline: Timer {
        interval: 16000
        onTriggered: {
            root.commandTimedOut = true;
            if (worker.running) worker.signal(9);
            else root.finish(3);
        }
    }
    // One event stream triggers bounded metadata reads; no interval polling.
    // startup inventory: cortetsu:connectivity-monitor
    readonly property Process monitor: Process {
        id: monitor
        command: ["nmcli", "monitor"]
        environment: ({ LC_ALL: "C", LANG: "C" })
        running: true
        onStarted: monitorHealthy.restart()
        stdout: SplitParser { onRead: data => root.monitorEvent(data) }
        stderr: SplitParser { onRead: data => { root.lastError = "NetworkManager no está disponible"; } }
        onExited: () => root.recoverMonitor()
        onRunningChanged: if (!running && !root.stopping) root.recoverMonitor()
    }
    readonly property Timer debounce: Timer {
        interval: 500
        onTriggered: {
            root.refreshRadio();
            root.enqueue("aps", ["-f", "IN-USE,BSSID,SSID,SIGNAL,FREQ,SECURITY,DEVICE", "device", "wifi", "list", "--rescan", "no"], {});
            root.refreshProfiles(root.profileEventPending);
            root.profileEventPending = false;
            for (const device of Object.keys(root.details)) root.refreshDetails(device);
        }
    }
    readonly property Timer monitorHealthy: Timer {
        interval: 30000
        onTriggered: root.monitorAttempts = 0
    }
    readonly property Timer recovery: Timer {
        onTriggered: if (!root.stopping) monitor.running = true
    }
    function recoverMonitor() {
        monitorHealthy.stop();
        if (stopping || recovery.running) return;
        lastError = "El monitor de NetworkManager se detuvo";
        if (monitorAttempts < 5) {
            monitorAttempts++;
            recovery.interval = Math.min(30000, 1000 * Math.pow(2, monitorAttempts - 1));
            recovery.restart();
        }
    }
    function ensureMonitor() {
        if (!monitor.running && !root.stopping) {
            monitorAttempts = 0;
            recovery.stop();
            monitor.running = true;
        }
    }
    Component.onCompleted: refresh()
    Component.onDestruction: {
        stopping = true;
        recovery.stop(); monitorHealthy.stop(); debounce.stop(); commandDeadline.stop();
        monitor.running = false; worker.running = false;
        queue = [];
    }
}
