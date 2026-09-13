pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import ".."
import "../../components"
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var candidateOutputs

    property var previewState: ({ active: false })
    property var lastResult: ({})
    property string statusText: qsTr("No hay vista previa activa")
    property string actionPath: ""
    property string previewCandidateJson: ""
    property string confirmedCandidateJson: ""

    readonly property string transactionPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-transaction"
    readonly property string persistPath: StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.local/bin/cortetsu-display-persist"
    readonly property bool active: previewState?.active ?? false
    readonly property real remaining: Number(previewState?.remaining_seconds ?? 0)
    readonly property string currentCandidateJson: JSON.stringify({ outputs: candidateOutputs })
    readonly property bool canPersist: !root.active && (root.lastResult?.confirmed ?? false) && root.confirmedCandidateJson.length > 0 && root.confirmedCandidateJson === root.currentCandidateJson

    function refresh(): void { if (!statusProbe.running) statusProbe.running = true; }

    function runTool(path, args): void {
        if (action.running) return;
        actionPath = path;
        action.command = [path].concat(args);
        action.running = true;
    }

    function startPreview(): void {
        if (!candidateOutputs.length) return;
        lastResult = ({});
        confirmedCandidateJson = "";
        previewCandidateJson = currentCandidateJson;
        statusText = qsTr("Iniciando vista previa…");
        runTool(transactionPath, ["preview", "--timeout", "15", "--candidate", previewCandidateJson]);
    }

    function confirm(): void {
        statusText = qsTr("Conservando durante esta sesión…");
        runTool(transactionPath, ["confirm"]);
    }

    function persist(): void {
        if (!canPersist) return;
        statusText = qsTr("Guardando de forma atómica…");
        runTool(persistPath, ["persist", "--candidate", confirmedCandidateJson]);
    }

    function revert(): void {
        statusText = qsTr("Restaurando distribución anterior…");
        confirmedCandidateJson = "";
        runTool(transactionPath, ["revert"]);
    }

    onCurrentCandidateJsonChanged: {
        if (confirmedCandidateJson.length > 0 && confirmedCandidateJson !== currentCandidateJson && !root.active)
        statusText = qsTr("La propuesta cambió · vuelve a previsualizar antes de guardar");
    }

    Component.onCompleted: refresh()

    Timer {
        interval: 500
        repeat: true
        running: root.active
        onTriggered: root.refresh()
    }

    Process {
        id: statusProbe
        command: [root.transactionPath, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.previewState = parsed;
                    if (parsed?.active)
                        root.statusText = qsTr("Reversión automática en %1 s").arg(Number(parsed?.remaining_seconds ?? 0).toFixed(1));
                    else if (!action.running && !(root.lastResult?.confirmed ?? false) && !(root.lastResult?.persisted ?? false))
                        root.statusText = qsTr("Reversión protegida");
                } catch (error) {
                        root.statusText = qsTr("Estado de vista previa no disponible");
                }
            }
        }
    }

    Process {
        id: action
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const parsed = JSON.parse(text.trim());
                    root.lastResult = parsed;
                    if (root.actionPath === root.persistPath) {
                        if (parsed?.ok && parsed?.persisted) {
                            root.statusText = qsTr("Guardado y verificado");
                        } else {
                            root.confirmedCandidateJson = "";
                            root.statusText = parsed?.error ?? qsTr("No se pudo guardar · se restauró el estado anterior");
                        }
                    } else if (parsed?.ok && parsed?.preview) {
                        root.statusText = qsTr("Vista previa activa · conservar o revertir");
                    } else if (parsed?.ok && parsed?.confirmed) {
                        root.confirmedCandidateJson = root.previewCandidateJson;
                        root.statusText = root.confirmedCandidateJson === root.currentCandidateJson
                            ? qsTr("Conservado · guarda para persistir")
                            : qsTr("La propuesta cambió · vuelve a previsualizar");
                    } else if (parsed?.ok && parsed?.reverted) {
                        root.confirmedCandidateJson = "";
                        root.statusText = qsTr("Distribución anterior restaurada");
                    } else if (!(parsed?.ok ?? false)) {
                        root.confirmedCandidateJson = "";
                        root.statusText = parsed?.error ?? qsTr("No se pudo ejecutar la acción de pantalla");
                    }
                } catch (error) {
                    root.confirmedCandidateJson = "";
                    root.statusText = qsTr("Acción de pantalla no disponible");
                }
                root.refresh();
            }
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingUnit
        spacing: CortetsuDesign.spacingCompact

        Row {
            width: parent.width
            height: 24

            CortetsuText {
                width: parent.width * 0.58
                text: qsTr("Aplicar de forma segura")
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                width: parent.width * 0.42
                text: root.active ? qsTr("%1 s").arg(root.remaining.toFixed(1)) : qsTr("reversión protegida")
                color: root.active ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOutline
                textSize: CortetsuTypography.labelSmallPx
                horizontalAlignment: Text.AlignRight
            }
        }

        CortetsuText {
            width: parent.width
            height: 24
            text: root.statusText
            color: root.active ? CortetsuDesign.colorPrimary : CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            elide: Text.ElideRight
        }

        Row {
            width: parent.width
            height: 38
            spacing: CortetsuDesign.spacingUnit

            CortetsuButton {
                width: (parent.width - parent.spacing * 3) / 4
                height: 38
                label: qsTr("Previsualizar")
                active: !root.active
                compact: true
                disabled: root.active || action.running
                focus: false
                onClicked: root.startPreview()
            }
            CortetsuButton {
                width: (parent.width - parent.spacing * 3) / 4
                height: 38
                label: qsTr("Conservar")
                active: root.active
                compact: true
                disabled: !root.active || action.running
                focus: false
                onClicked: root.confirm()
            }
            CortetsuButton {
                width: (parent.width - parent.spacing * 3) / 4
                height: 38
                label: qsTr("Guardar")
                active: root.canPersist
                compact: true
                disabled: !root.canPersist || action.running
                focus: false
                onClicked: root.persist()
            }
            CortetsuButton {
                width: (parent.width - parent.spacing * 3) / 4
                height: 38
                label: qsTr("Revertir")
                danger: root.active
                compact: true
                disabled: !root.active || action.running
                focus: false
                onClicked: root.revert()
            }
        }
    }
}
