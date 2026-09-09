pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../components"
import ".."
import "../CortetsuDesign.js" as CortetsuDesign
import "../CortetsuTypography.js" as CortetsuTypography

Item {
    id: root

    required property var screenState
    property var pomodoro: ({})
    property double nowMs: Date.now()

    readonly property string statePath: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/cortetsu/pomodoro.json`
    readonly property string helperPath: `${Quickshell.env("HOME")}/.local/bin/cortetsu-pomodoro`
    readonly property string actionLabel: pomodoro.phase === "PAUSED"
        ? qsTr("Resume")
        : isActivePhase(pomodoro.phase)
            ? qsTr("Pause")
            : qsTr("Start")
    readonly property string actionIcon: pomodoro.phase === "PAUSED"
        ? "play_arrow"
        : isActivePhase(pomodoro.phase)
            ? "pause"
            : "play_arrow"

    function isBreakPhase(phase): bool {
        return phase === "BREAK" || phase === "LONG_BREAK";
    }

    function isActivePhase(phase): bool {
        return phase === "FOCUS" || isBreakPhase(phase);
    }

    function phaseDurationMs(phase): double {
        if (phase === "LONG_BREAK")
            return Number(pomodoro.longBreakMinutes || 15) * 60000;
        if (phase === "BREAK")
            return Number(pomodoro.shortBreakMinutes || 5) * 60000;
        return Number(pomodoro.focusMinutes || 25) * 60000;
    }

    function remainingMs(): double {
        if (pomodoro.phase === "PAUSED")
            return Math.max(0, Number(pomodoro.pausedRemainingMs || 0));
        if (isActivePhase(pomodoro.phase))
            return Math.max(0, Number(pomodoro.targetEndTimestamp || 0) * 1000 - nowMs);
        return phaseDurationMs("FOCUS");
    }

    function timeLeft(): string {
        const ms = remainingMs();
        return `${String(Math.floor(ms / 60000)).padStart(2, "0")}:${String(Math.floor(ms / 1000) % 60).padStart(2, "0")}`;
    }

    function progress(): double {
        const phase = pomodoro.phase === "PAUSED" ? (pomodoro.pausedPhase || "FOCUS") : pomodoro.phase;
        if (!isActivePhase(phase))
            return 0;
        return Math.max(0, Math.min(1, 1 - remainingMs() / Math.max(1, phaseDurationMs(phase))));
    }

    function phaseLabel(): string {
        if (pomodoro.phase === "FOCUS")
            return qsTr("Focus session");
        if (pomodoro.phase === "BREAK")
            return qsTr("Short break");
        if (pomodoro.phase === "LONG_BREAK")
            return qsTr("Long break");
        if (pomodoro.phase === "PAUSED")
            return qsTr("Paused");
        return qsTr("Ready to focus");
    }

    function loadPomodoro(): void {
        try {
            pomodoro = JSON.parse(stateFile.text());
        } catch (_) {
            pomodoro = {};
        }
    }

    function runPomodoro(command: string): void {
        if (actionProcess.running)
            return;

        const next = Object.assign({}, pomodoro);
        const now = Date.now();
        root.nowMs = now;

        if (command === "start") {
            next.phase = "FOCUS";
            next.targetEndTimestamp = now / 1000 + Number(next.focusMinutes || 25) * 60;
            next.pausedRemainingMs = 0;
            next.pausedPhase = "FOCUS";
        } else if (command === "pause" && isActivePhase(next.phase)) {
            next.pausedRemainingMs = Math.max(0, Number(next.targetEndTimestamp || 0) * 1000 - now);
            next.pausedPhase = next.phase;
            next.targetEndTimestamp = 0;
            next.phase = "PAUSED";
        } else if (command === "resume" && next.phase === "PAUSED") {
            next.phase = next.pausedPhase || "FOCUS";
            next.targetEndTimestamp = now / 1000 + Number(next.pausedRemainingMs || 0) / 1000;
            next.pausedRemainingMs = 0;
        } else if (command === "skip" && isBreakPhase(next.phase)) {
            next.phase = "FOCUS";
            next.targetEndTimestamp = now / 1000 + Number(next.focusMinutes || 25) * 60;
            next.pausedRemainingMs = 0;
            next.pausedPhase = "FOCUS";
        } else if (command === "reset") {
            next.phase = "IDLE";
            next.targetEndTimestamp = 0;
            next.pausedRemainingMs = 0;
            next.pausedPhase = "FOCUS";
            next.completedSessions = 0;
        }

        root.pomodoro = next;
        actionProcess.command = [root.helperPath, command];
        actionProcess.running = true;
    }

    function togglePrimary(): void {
        if (pomodoro.phase === "PAUSED")
            runPomodoro("resume");
        else if (isActivePhase(pomodoro.phase))
            runPomodoro("pause");
        else
            runPomodoro("start");
    }

    Component.onCompleted: loadPomodoro()

    FileView {
        id: stateFile
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: root.loadPomodoro()
        onFileChanged: reloadTimer.restart()
    }

    Process {
        id: actionProcess
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.pomodoro = JSON.parse(text.trim());
                } catch (_) {
                    reloadTimer.restart();
                }
            }
        }
        onExited: reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 60
        repeat: false
        onTriggered: root.loadPomodoro()
    }

    Timer {
        interval: 1000
        repeat: true
        running: (root.screenState?.dashboard ?? false) && root.isActivePhase(root.pomodoro.phase)
        onTriggered: root.nowMs = Date.now()
    }

    CortetsuSurface {
        anchors.fill: parent
        radiusValue: CortetsuDesign.radiusLarge
        baseColor: Qt.alpha(CortetsuDesign.colorPrimaryContainer, 0.22)
        outlined: true
        outlineColor: Qt.alpha(CortetsuDesign.colorPrimary, 0.26)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true

            CortetsuText {
                text: qsTr("FOCUS")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorPrimary
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            CortetsuText {
                text: qsTr("%1 sessions").arg(Number(root.pomodoro.completedSessions || 0))
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorOnSurfaceVariant
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingStandard

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                CortetsuText {
                    text: root.timeLeft()
                    textSize: 30
                    font.weight: Font.DemiBold
                }

                CortetsuText {
                    Layout.fillWidth: true
                    text: root.phaseLabel()
                    textSize: CortetsuTypography.bodySmallPx
                    color: CortetsuDesign.colorOnSurfaceVariant
                    elide: Text.ElideRight
                }
            }

            CortetsuButton {
                compact: true
                icon: root.actionIcon
                label: root.actionLabel
                active: root.isActivePhase(root.pomodoro.phase)
                disabled: actionProcess.running
                onClicked: root.togglePrimary()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 4
            radius: 2
            color: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.28)

            Rectangle {
                width: parent.width * root.progress()
                height: parent.height
                radius: parent.radius
                color: CortetsuDesign.colorPrimary

                Behavior on width {
                    NumberAnimation {
                        duration: CortetsuDesign.motionStandardMs
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.pomodoro.phase !== "IDLE" && root.pomodoro.phase !== undefined

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                icon: root.isBreakPhase(root.pomodoro.phase) ? "skip_next" : "restart_alt"
                label: root.isBreakPhase(root.pomodoro.phase) ? qsTr("Skip") : qsTr("Reset")
                disabled: actionProcess.running
                onClicked: root.runPomodoro(root.isBreakPhase(root.pomodoro.phase) ? "skip" : "reset")
            }
        }
    }
}
