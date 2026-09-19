pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Mutating NetworkManager operations for Settings. CortetsuNetwork remains the
// lightweight reactive status source used by the bar and OSD.
Singleton {
    id: root

    property string state: "idle"
    property string operation: ""
    property string error: ""
    property string lastMessage: ""
    property bool wifiEnabled: true
    property string activeSsid: ""
    property string activeDevice: ""
    property list<var> networks: []
    property list<var> profiles: []
    property var activeDetails: ({ device: "", address: "", gateway: "", dns: [] })
    property string detailsState: "idle"
    property string detailsError: ""
    property string detailsDevice: ""
    property string detailsOutput: ""
    property string detailsErrorOutput: ""
    property string secretProfile: ""
    property string secretState: "idle"
    property string secretError: ""
    property string secretOutput: ""
    property string secretErrorOutput: ""
    readonly property bool busy: command.running
    readonly property bool detailsBusy: detailsCommand.running
    readonly property bool secretBusy: secretCommand.running
    readonly property bool activeBusy: activeCommand.running
    property var pending: ({ kind: "", args: [] })
    property string commandOutput: ""
    property string commandError: ""
    property string activeOutput: ""
    property string activeErrorOutput: ""
    property int initialStep: 0

    readonly property Process command: Process {
        id: command
        command: ["nmcli", ...root.pending.args]
        stdout: StdioCollector { onStreamFinished: root.commandOutput = text }
        stderr: StdioCollector { onStreamFinished: root.commandError = text }
        onExited: root.finish(command.exitCode)
    }

    readonly property Process detailsCommand: Process {
        id: detailsCommand
        command: ["nmcli", "-t", "--escape", "yes", "-f", "GENERAL.DEVICE,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS", "device", "show", root.detailsDevice]
        stdout: StdioCollector { onStreamFinished: root.detailsOutput = text }
        stderr: StdioCollector { onStreamFinished: root.detailsErrorOutput = text }
        onExited: root.finishDetails(detailsCommand.exitCode)
    }

    readonly property Process secretCommand: Process {
        id: secretCommand
        command: ["nmcli", "--show-secrets", "-t", "--escape", "yes", "-f", "802-11-wireless-security.psk", "connection", "show", "id", root.secretProfile]
        stdout: StdioCollector { onStreamFinished: root.secretOutput = text }
        stderr: StdioCollector { onStreamFinished: root.secretErrorOutput = text }
        onExited: root.finishSecret(secretCommand.exitCode)
    }

    readonly property Process activeCommand: Process {
        id: activeCommand
        command: ["nmcli", "-t", "--escape", "yes", "-f", "NAME,TYPE,DEVICE", "connection", "show", "--active"]
        stdout: StdioCollector { onStreamFinished: root.activeOutput = text }
        stderr: StdioCollector { onStreamFinished: root.activeErrorOutput = text }
        onExited: root.finishActive(activeCommand.exitCode)
    }

    function splitFields(line: string): list<string> {
        const fields = [];
        let field = "";
        let escaped = false;
        for (const character of line) {
            if (escaped) {
                field += character;
                escaped = false;
            } else if (character === "\\") {
                escaped = true;
            } else if (character === ":") {
                fields.push(field.trim());
                field = "";
            } else {
                field += character;
            }
        }
        if (escaped)
            field += "\\";
        fields.push(field.trim());
        return fields;
    }

    function run(kind: string, args: list<string>): void {
        if (command.running)
            return;
        pending = { kind: kind, args: args };
        operation = kind;
        state = "loading";
        error = "";
        lastMessage = "";
        commandOutput = "";
        commandError = "";
        command.running = true;
    }

    function refresh(): void { run("refresh", ["-t", "-f", "WIFI", "general"]); }
    function refreshNetworks(): void {
        run("networks", ["-t", "--escape", "yes", "-f", "IN-USE,SIGNAL,SSID,SECURITY,DEVICE", "device", "wifi", "list"]);
    }
    function refreshProfiles(): void {
        run("profiles", ["-t", "--escape", "yes", "-f", "NAME,TYPE,AUTOCONNECT", "connection", "show"]);
    }

    function refreshAll(): void {
        if (command.running)
            return;
        initialStep = 0;
        initializeNext();
    }

    function refreshDetails(device: string): void {
        if (!device.trim() || detailsCommand.running)
            return;
        detailsDevice = device.trim();
        detailsState = "loading";
        detailsError = "";
        detailsOutput = "";
        detailsErrorOutput = "";
        detailsCommand.running = true;
    }

    function copyPassword(profile: string): void {
        if (!profile.trim() || secretCommand.running)
            return;
        secretProfile = profile.trim();
        secretState = "loading";
        secretError = "";
        secretOutput = "";
        secretErrorOutput = "";
        secretCommand.running = true;
    }

    function refreshActive(): void {
        if (activeCommand.running)
            return;
        activeOutput = "";
        activeErrorOutput = "";
        activeCommand.running = true;
    }

    function initializeNext(): void {
        if (initialStep === 0) {
            initialStep = 1;
            refresh();
        } else if (initialStep === 1) {
            initialStep = 2;
            refreshNetworks();
        } else if (initialStep === 2) {
            initialStep = 3;
            refreshProfiles();
        } else if (initialStep === 3) {
            initialStep = 4;
            refreshActive();
        }
    }
    function setWifi(enabled: bool): void {
        run(enabled ? "wifi-on" : "wifi-off", ["radio", "wifi", enabled ? "on" : "off"]);
    }
    function connect(ssid, password): void {
        if (!ssid.trim()) {
            state = "error";
            error = qsTr("El nombre de la red está vacío");
            return;
        }
        const args = ["device", "wifi", "connect", ssid];
        if (password.length > 0)
            args.push("password", password);
        run("connect", args);
    }
    function disconnect(profile: string): void {
        if (profile.trim()) run("disconnect", ["connection", "down", "id", profile]);
    }
    function forget(profile: string): void {
        if (profile.trim()) run("forget", ["connection", "delete", "id", profile]);
    }
    function setAutoconnect(profile: string, enabled: bool): void {
        if (profile.trim()) run("autoconnect", ["connection", "modify", profile, "connection.autoconnect", enabled ? "yes" : "no"]);
    }

    function finishDetails(exitCode: int): void {
        if (exitCode !== 0) {
            detailsState = "error";
            detailsError = (detailsErrorOutput || detailsOutput || qsTr("No se pudieron leer los detalles de la conexión")).trim();
            return;
        }
        const details = { device: detailsDevice, address: "", gateway: "", dns: [] };
        for (const line of detailsOutput.trim().split("\n").filter(Boolean)) {
            const fields = splitFields(line);
            const key = fields.shift() ?? "";
            const baseKey = key.split("[")[0];
            const value = fields.join(":").trim();
            if (key === "GENERAL.DEVICE")
                details.device = value;
            else if (baseKey === "IP4.ADDRESS" && details.address.length === 0)
                details.address = value.split("/")[0];
            else if (baseKey === "IP4.GATEWAY" && details.gateway.length === 0)
                details.gateway = value;
            else if (baseKey === "IP4.DNS" && value.length > 0 && !details.dns.includes(value))
                details.dns.push(value);
        }
        activeDetails = details;
        detailsState = "ready";
    }

    function finishSecret(exitCode: int): void {
        if (exitCode !== 0) {
            secretState = "error";
            secretError = (secretErrorOutput || secretOutput || qsTr("NetworkManager no entregó la contraseña")).trim();
            return;
        }
        const value = secretOutput.trim().split("\n").filter(Boolean).map(line => {
            const fields = splitFields(line);
            fields.shift();
            return fields.join(":").trim();
        }).find(line => line.length > 0) ?? "";
        if (value.length === 0) {
            secretState = "error";
            secretError = qsTr("Este perfil no tiene una contraseña disponible");
            return;
        }
        Quickshell.clipboardText = value;
        secretState = "ready";
    }

    function finishActive(exitCode: int): void {
        if (exitCode !== 0) {
            activeSsid = "";
            activeDevice = "";
            return;
        }
        const active = activeOutput.trim().split("\n").filter(Boolean).map(line => {
            const fields = splitFields(line);
            return { name: fields[0] ?? "", type: fields[1] ?? "", device: fields[2] ?? "" };
        }).find(connection => connection.type === "802-11-wireless") ?? null;
        activeSsid = active?.name ?? "";
        activeDevice = active?.device ?? "";
    }

    function finish(exitCode: int): void {
        if (exitCode !== 0) {
            state = "error";
            error = (commandError || commandOutput || qsTr("NetworkManager rechazó la operación")).trim();
            return;
        }
        const kind = pending.kind;
        if (kind === "refresh") {
            wifiEnabled = commandOutput.toLowerCase().includes("enabled");
        } else if (kind === "networks") {
            networks = commandOutput.trim().split("\n").filter(Boolean).map(line => {
                const fields = splitFields(line);
                return { active: fields[0] === "*", signal: Number(fields[1]) || 0,
                    ssid: fields[2] ?? "", security: fields[3] ?? "", device: fields[4] ?? "" };
            }).filter(network => network.ssid.length > 0);
            activeSsid = networks.find(network => network.active)?.ssid ?? "";
        } else if (kind === "profiles") {
            profiles = commandOutput.trim().split("\n").filter(Boolean).map(line => {
                const fields = splitFields(line);
                return { name: fields[0] ?? "", type: fields[1] ?? "", autoconnect: fields[2] === "yes" };
            }).filter(profile => profile.name.length > 0);
            if (initialStep > 0 && initialStep < 4)
                Qt.callLater(initializeNext);
        } else {
            lastMessage = kind === "wifi-on" ? qsTr("Wi‑Fi activado")
                : kind === "wifi-off" ? qsTr("Wi‑Fi apagado")
                : kind === "connect" ? qsTr("Conexión iniciada")
                : kind === "forget" ? qsTr("Perfil eliminado")
                : qsTr("Cambios aplicados");
        }
        state = "ready";
        if (kind !== "profiles" && initialStep > 0 && initialStep < 3)
            Qt.callLater(initializeNext);
    }

    Component.onCompleted: initializeNext()
}
