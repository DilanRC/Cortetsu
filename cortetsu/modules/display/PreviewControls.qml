pragma ComponentBehavior: Bound

import QtQuick
import QtCore
import Quickshell
import Quickshell.Io
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var candidateOutputs

    property var previewState: ({ active: false })
    property var lastResult: ({})
    property string statusText: qsTr("No active preview")
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
        statusText = qsTr("Starting preview…");
        runTool(transactionPath, ["preview", "--timeout", "15", "--candidate", previewCandidateJson]);
    }

    function confirm(): void {
        statusText = qsTr("Keeping for this session…");
        runTool(transactionPath, ["confirm"]);
    }

    function persist(): void {
        if (!canPersist) return;
        statusText = qsTr("Saving atomically…");
        runTool(persistPath, ["persist", "--candidate", confirmedCandidateJson]);
    }

    function revert(): void {
        statusText = qsTr("Restoring previous layout…");
        confirmedCandidateJson = "";
        runTool(transactionPath, ["revert"]);
    }

    onCurrentCandidateJsonChanged: {
        if (confirmedCandidateJson.length > 0 && confirmedCandidateJson !== currentCandidateJson && !root.active)
            statusText = qsTr("Candidate changed · preview again before Save");
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
                        root.statusText = qsTr("Auto-revert in %1 s").arg(Number(parsed?.remaining_seconds ?? 0).toFixed(1));
                    else if (!action.running && !(root.lastResult?.confirmed ?? false) && !(root.lastResult?.persisted ?? false))
                        root.statusText = qsTr("Rollback protected");
                } catch (error) {
                    root.statusText = qsTr("Preview status unavailable");
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
                            root.statusText = qsTr("Saved and verified");
                        } else {
                            root.confirmedCandidateJson = "";
                            root.statusText = parsed?.error ?? qsTr("Save failed · previous state restored");
                        }
                    } else if (parsed?.ok && parsed?.preview) {
                        root.statusText = qsTr("Preview active · Keep or Revert");
                    } else if (parsed?.ok && parsed?.confirmed) {
                        root.confirmedCandidateJson = root.previewCandidateJson;
                        root.statusText = root.confirmedCandidateJson === root.currentCandidateJson
                            ? qsTr("Kept · Save to persist")
                            : qsTr("Candidate changed · preview again");
                    } else if (parsed?.ok && parsed?.reverted) {
                        root.confirmedCandidateJson = "";
                        root.statusText = qsTr("Previous layout restored");
                    } else if (!(parsed?.ok ?? false)) {
                        root.confirmedCandidateJson = "";
                        root.statusText = parsed?.error ?? qsTr("Display action failed");
                    }
                } catch (error) {
                    root.confirmedCandidateJson = "";
                    root.statusText = qsTr("Display action unavailable");
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
                text: qsTr("Apply safely")
                color: CortetsuDesign.colorOnSurface
                textSize: CortetsuTypography.titleSmallPx
                font.weight: Font.DemiBold
            }
            CortetsuText {
                width: parent.width * 0.42
                text: root.active ? qsTr("%1 s").arg(root.remaining.toFixed(1)) : qsTr("rollback protected")
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

            ActionButton {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Preview")
                active: !root.active
                enabled: !root.active && !action.running
                onTriggered: root.startPreview()
            }
            ActionButton {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Keep")
                active: root.active
                enabled: root.active && !action.running
                onTriggered: root.confirm()
            }
            ActionButton {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Save")
                active: root.canPersist
                enabled: root.canPersist && !action.running
                onTriggered: root.persist()
            }
            ActionButton {
                width: (parent.width - parent.spacing * 3) / 4
                label: qsTr("Revert")
                danger: root.active
                enabled: root.active && !action.running
                onTriggered: root.revert()
            }
        }
    }

    component ActionButton: Item {
        required property string label
        property bool active: false
        property bool danger: false
        signal triggered()

        height: 38
        opacity: enabled ? 1 : 0.38

        CortetsuSurface {
            anchors.fill: parent
            radiusValue: CortetsuDesign.radiusMedium
            baseColor: parent.danger
                ? Qt.alpha(CortetsuDesign.colorVermillion, 0.42)
                : parent.active
                    ? Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.82)
                    : buttonLayer.containsMouse
                        ? CortetsuDesign.colorSurfaceGlass
                        : "transparent"
            outlined: false
        }
        CortetsuStateLayer {
            id: buttonLayer
            anchors.fill: parent
            radius: CortetsuDesign.radiusMedium
            disabled: !parent.enabled
            onClicked: parent.triggered()
        }
        CortetsuText {
            anchors.centerIn: parent
            text: parent.label
            color: parent.danger || parent.active
                ? CortetsuDesign.colorOnSurface
                : CortetsuDesign.colorOnSurfaceVariant
            textSize: CortetsuTypography.labelSmallPx
            font.weight: parent.active ? Font.DemiBold : Font.Normal
        }
    }
}
