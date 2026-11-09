pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell.Io

// Named arrangements saved by cortetsu-display-presets. Loading one only
// fills the proposal: it still has to be previewed and kept.
Item {
    id: root

    property var presets: []
    property string state: "idle"   // idle | busy | error
    property string message: ""
    property string actionKind: ""

    readonly property string helperPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-presets"

    signal loaded(var outputs, string name)

    function run(kind, args): void {
        if (worker.running)
            return;
        actionKind = kind;
        state = "busy";
        worker.command = [helperPath, kind].concat(args);
        worker.running = true;
    }

    function refresh(): void { run("list", []); }
    function save(name, outputs): void { run("save", ["--name", name, "--candidate", JSON.stringify({ outputs: outputs })]); }
    function load(name): void { run("get", ["--name", name]); }
    function remove(name): void { run("delete", ["--name", name]); }

    Component.onCompleted: refresh()

    // startup inventory: cortetsu:display-presets
    Process {
        id: worker
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text.trim());
                } catch (error) {
                    root.state = "error";
                    root.message = qsTr("El servicio de distribuciones no respondió");
                    return;
                }
                if (!(parsed?.ok ?? false)) {
                    root.state = "error";
                    root.message = parsed?.error ?? qsTr("No se pudo completar la acción");
                    return;
                }
                root.state = "idle";
                root.message = "";
                if (root.actionKind === "list")
                    root.presets = parsed?.presets ?? [];
                else if (root.actionKind === "get")
                    root.loaded(parsed?.preset?.candidate?.outputs ?? [], parsed?.name ?? "");
                else
                    Qt.callLater(root.refresh);
            }
        }
    }
}
