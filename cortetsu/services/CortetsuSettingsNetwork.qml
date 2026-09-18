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
    property list<var> networks: []
    property list<var> profiles: []
    readonly property bool busy: command.running
    property var pending: ({ kind: "", args: [] })
    property string commandOutput: ""
    property string commandError: ""
    property int initialStep: 0

    readonly property Process command: Process {
        id: command
        command: ["nmcli", ...root.pending.args]
        stdout: StdioCollector { onStreamFinished: root.commandOutput = text }
        stderr: StdioCollector { onStreamFinished: root.commandError = text }
        onExited: root.finish(command.exitCode)
    }

    function splitFields(line: string): list<string> {
        return line.split(":").map(field => field.replace(/\\:/g, ":").trim());
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
        } else {
            lastMessage = kind === "wifi-on" ? qsTr("Wi‑Fi activado")
                : kind === "wifi-off" ? qsTr("Wi‑Fi apagado")
                : kind === "connect" ? qsTr("Conexión iniciada")
                : kind === "forget" ? qsTr("Perfil eliminado")
                : qsTr("Cambios aplicados");
        }
        state = "ready";
        if (initialStep > 0 && initialStep < 3)
            Qt.callLater(initializeNext);
    }

    Component.onCompleted: initializeNext()
}
