pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import "DisplayLayout.js" as Arrange

// The display arrangement being edited. It reads the live outputs with
// cortetsu-display-probe and validates a proposal with cortetsu-display-plan
// (a dry run: nothing changes). Applying goes through DisplayTransaction.
Item {
    id: root

    property var snapshot: ({})
    property var candidateOutputs: []
    property int selectedIndex: 0
    property var planResult: ({})
    property string planState: "idle"   // idle | running | ok | blocked | error
    property string probeState: "idle"  // idle | running | ok | error
    property string message: ""

    readonly property string probePath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-probe"
    readonly property string plannerPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-plan"
    readonly property var monitors: snapshot?.hyprland ?? []
    readonly property var selected: candidateOutputs[selectedIndex] ?? null
    readonly property var selectedLive: live(selected?.name ?? "")
    readonly property int enabledCount: candidateOutputs.filter(item => item?.enabled ?? true).length
    readonly property bool changed: JSON.stringify(candidateOutputs) !== JSON.stringify(Arrange.fromMonitors(monitors))
    readonly property bool planning: planner.running

    signal planFinished(bool ok)

    function live(name): var {
        return monitors.find(monitor => monitor?.name === name) ?? ({});
    }

    // resetProposal: rebuild the proposal from what the probe returns. Kept
    // false after Conservar, so the kept proposal stays the one Guardar saves.
    // An edit made while the probe runs wins over the pending rebuild.
    property bool resetOnProbe: false
    property int edits: 0
    property int editsAtRequest: 0

    function refresh(resetProposal): void {
        if (resetProposal) {
            resetOnProbe = true;
            editsAtRequest = edits;
        }
        if (probe.running)
            return;
        probeState = "running";
        probe.running = true;
    }

    function reset(): void {
        candidateOutputs = Arrange.fromMonitors(monitors);
        selectedIndex = Math.max(0, Math.min(selectedIndex, candidateOutputs.length - 1));
        planResult = ({});
        planState = "idle";
        message = "";
    }

    function replace(outputs, note): void {
        edits += 1;
        candidateOutputs = outputs;
        planResult = ({});
        planState = "idle";
        message = note ?? "";
    }

    function update(field, value): void {
        if (!selected)
            return;
        const next = candidateOutputs.map(item => Object.assign({}, item));
        next[selectedIndex][field] = value;
        replace(["mode", "scale", "transform"].includes(field) ? Arrange.reflow(candidateOutputs, next, selectedIndex) : next);
    }

    function setEnabled(value): void {
        if (!value && (selected?.enabled ?? true) && enabledCount <= 1) {
            message = qsTr("Al menos una pantalla debe seguir activa");
            return;
        }
        update("enabled", value);
    }

    // A resolution keeps the refresh rate closest to the current one.
    function setResolution(size): void {
        update("mode", Arrange.modeFor(selectedLive?.available_modes ?? [], size, Arrange.parseMode(selected?.mode).refresh));
    }

    function setRefresh(rate): void {
        const size = Arrange.parseMode(selected?.mode);
        update("mode", Arrange.modeFor(selectedLive?.available_modes ?? [], `${size.width}x${size.height}`, rate));
    }

    // Dragging in the arrangement: snapped to the other outputs' edges.
    function move(index, x, y): void {
        if (index < 0 || index >= candidateOutputs.length)
            return;
        const next = candidateOutputs.map(item => Object.assign({}, item));
        const snapped = Arrange.snap(next, index, x, y);
        next[index].x = snapped.x;
        next[index].y = snapped.y;
        replace(next);
    }

    function preset(kind): void {
        const result = Arrange.preset(candidateOutputs, kind);
        if (!result.ok) {
            message = result.reason;
            return;
        }
        selectedIndex = result.selected;
        replace(result.outputs, result.reason);
    }

    function runPlan(): void {
        if (planner.running || !candidateOutputs.length)
            return;
        planState = "running";
        planner.command = [plannerPath, "--candidate", JSON.stringify({ outputs: candidateOutputs })];
        planner.running = true;
    }

    // startup inventory: cortetsu:display-probe
    Process {
        id: probe
        command: [root.probePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.snapshot = JSON.parse(text.trim());
                    root.probeState = "ok";
                    if (!root.candidateOutputs.length || (root.resetOnProbe && root.edits === root.editsAtRequest))
                        root.reset();
                    root.resetOnProbe = false;
                } catch (error) {
                    root.probeState = "error";
                    root.message = qsTr("No se pudo leer el inventario de pantallas");
                }
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.probeState = "error";
                root.message = qsTr("cortetsu-display-probe no respondió");
            }
        }
    }

    Process {
        id: planner
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.planResult = JSON.parse(text.trim());
                    root.planState = root.planResult?.ok ? "ok" : "blocked";
                } catch (error) {
                    root.planResult = ({ ok: false, errors: [qsTr("El planificador devolvió una respuesta ilegible")] });
                    root.planState = "error";
                }
                root.planFinished(root.planState === "ok");
            }
        }
    }

    // A monitor plugged or unplugged while the page is open; an edited
    // proposal is kept, an untouched one follows the new outputs.
    Connections {
        target: Quickshell
        function onScreensChanged(): void { root.refresh(!root.changed); }
    }

    Component.onCompleted: refresh()
}
