pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell.Io

// Applying a display arrangement safely. cortetsu-display-transaction applies
// the candidate for a few seconds and starts its own watchdog process, which
// restores the previous arrangement unless "confirm" arrives in time, even if
// Settings or the shell goes away. Only a confirmed candidate can be saved,
// and cortetsu-display-persist writes it with a backup.
Item {
    id: root

    required property var candidateOutputs

    property var previewState: ({ active: false })
    property var lastResult: ({})
    property string phase: "idle"   // idle | previewing | confirmed | saved | reverted | failed
    property string message: ""
    property string actionPath: ""
    property string previewCandidateJson: ""
    property string confirmedCandidateJson: ""

    readonly property int previewSeconds: 15
    readonly property string transactionPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-transaction"
    readonly property string persistPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-persist"
    readonly property bool active: previewState?.active ?? false
    readonly property real remaining: Number(previewState?.remaining_seconds ?? 0)
    readonly property bool working: action.running
    readonly property string currentCandidateJson: JSON.stringify({ outputs: candidateOutputs })
    readonly property bool canSave: !active && phase === "confirmed"
        && confirmedCandidateJson.length > 0 && confirmedCandidateJson === currentCandidateJson

    function refresh(): void {
        if (!statusProbe.running)
            statusProbe.running = true;
    }

    function run(path, args): void {
        if (action.running)
            return;
        actionPath = path;
        action.command = [path].concat(args);
        action.running = true;
    }

    function preview(): void {
        if (!candidateOutputs.length || active)
            return;
        confirmedCandidateJson = "";
        previewCandidateJson = currentCandidateJson;
        message = "";
        run(transactionPath, ["preview", "--timeout", String(previewSeconds), "--candidate", previewCandidateJson]);
    }

    function confirm(): void { run(transactionPath, ["confirm"]); }

    function revert(): void {
        confirmedCandidateJson = "";
        run(transactionPath, ["revert"]);
    }

    function save(): void {
        if (canSave)
            run(persistPath, ["persist", "--candidate", confirmedCandidateJson]);
    }

    function fail(text): void {
        confirmedCandidateJson = "";
        phase = "failed";
        message = text;
    }

    // Editing after Conservar means the saved candidate would differ from
    // what was tested: it has to be previewed again.
    onCurrentCandidateJsonChanged: if (phase === "confirmed" && confirmedCandidateJson !== currentCandidateJson) phase = "idle"

    Component.onCompleted: refresh()

    // Polls only while a preview is counting down.
    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    // startup inventory: cortetsu:display-preview-status
    Process {
        id: statusProbe
        command: [root.transactionPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    const wasActive = root.active;
                    root.previewState = parsed;
                    // The watchdog restored the arrangement on its own.
                    if (wasActive && !parsed?.active && root.phase === "previewing" && !action.running) {
                        root.phase = "reverted";
                        root.message = qsTr("No se confirmó a tiempo: se restauró la distribución anterior");
                    }
                    if (parsed?.active && root.phase !== "previewing")
                        root.phase = "previewing";
                } catch (error) {
                    root.message = qsTr("Estado de la vista previa no disponible");
                }
            }
        }
    }

    Process {
        id: action
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                let parsed = null;
                try {
                    parsed = JSON.parse(text.trim());
                } catch (error) {
                    root.fail(qsTr("La herramienta de pantallas no respondió"));
                    root.refresh();
                    return;
                }
                root.lastResult = parsed;
                if (!(parsed?.ok ?? false))
                    root.fail(parsed?.error ?? qsTr("No se pudo aplicar el cambio de pantalla"));
                else if (root.actionPath === root.persistPath) {
                    root.phase = parsed?.persisted ? "saved" : "failed";
                    root.message = parsed?.persisted ? qsTr("Guardado: se mantendrá al reiniciar")
                        : (parsed?.error ?? qsTr("No se pudo guardar; se restauró el estado anterior"));
                } else if (parsed?.preview) {
                    root.phase = "previewing";
                } else if (parsed?.confirmed) {
                    root.confirmedCandidateJson = root.previewCandidateJson;
                    root.phase = "confirmed";
                    root.message = qsTr("Conservado en esta sesión. Guarda para mantenerlo al reiniciar.");
                } else if (parsed?.reverted) {
                    root.phase = "reverted";
                    root.message = qsTr("Se restauró la distribución anterior");
                }
                root.refresh();
            }
        }
    }
}
