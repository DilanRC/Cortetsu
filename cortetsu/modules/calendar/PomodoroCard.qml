pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../../components"
import "../../theme"
import "../pomodoro"
import "../pomodoro/PomodoroModel.js" as Model
import "../CortetsuTypography.js" as CortetsuTypography

// Pomodoro card of the Calendar surface. It shows the helper's state and sends
// its commands; the countdown ticks once a second only while the card is on
// screen and a phase is running.
CortetsuSurface {
    id: card

    readonly property var pomodoroState: Pomodoro.state
    readonly property string phase: Pomodoro.phase
    property double nowMs: Date.now()

    function phaseLabel(): string {
        if (phase === "FOCUS") return qsTr("Concentración");
        if (phase === "BREAK") return qsTr("Descanso corto");
        if (phase === "LONG_BREAK") return qsTr("Descanso largo");
        if (phase === "PAUSED") return qsTr("En pausa");
        return qsTr("Listo para concentrarse");
    }

    function sessionsLabel(count: int): string {
        return count === 1 ? qsTr("1 sesión") : qsTr("%1 sesiones").arg(count);
    }

    outlined: false
    radius: CortetsuDesign.radiusMedium
    color: CortetsuDesign.colorSecondaryContainer
    onPomodoroStateChanged: nowMs = Date.now()

    SystemClock {
        enabled: card.visible && Pomodoro.running
        precision: SystemClock.Seconds
        onDateChanged: card.nowMs = Date.now()
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: CortetsuDesign.spacingStandard
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            CortetsuText { Layout.fillWidth: true; text: card.phaseLabel(); color: CortetsuDesign.colorOnSecondaryContainer; textSize: CortetsuTypography.labelLargePx }
            CortetsuText { text: card.sessionsLabel(Number(card.pomodoroState.completedSessions || 0)); color: CortetsuDesign.colorOnSecondaryContainer; textSize: CortetsuTypography.labelSmallPx }
        }
        CortetsuText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Model.timeLeft(card.pomodoroState, card.nowMs)
            color: CortetsuDesign.colorOnSecondaryContainer
            textSize: CortetsuTypography.titleLargePx
        }
        CortetsuProgressBar {
            Layout.fillWidth: true
            value: Model.progress(card.pomodoroState, card.nowMs)
            barHeight: 5
            barRadius: 3
            trackColor: CortetsuDesign.colorSecondary
            fillColor: CortetsuDesign.colorOnSecondaryContainer
            motionDuration: CortetsuDesign.motionFastMs
        }
        RowLayout {
            Layout.fillWidth: true
            Item { Layout.fillWidth: true }
            CortetsuButton {
                visible: Model.isBreak(card.phase)
                compact: true
                icon: "skip_next"
                label: qsTr("Saltar descanso")
                onClicked: Pomodoro.run("skip")
            }
            CortetsuButton {
                readonly property string command: Model.primaryCommand(card.pomodoroState)
                compact: true
                icon: command === "pause" ? "pause" : "play_arrow"
                label: command === "pause" ? qsTr("Pausar") : command === "resume" ? qsTr("Reanudar") : qsTr("Iniciar")
                onClicked: Pomodoro.run(command)
            }
            CortetsuButton {
                compact: true
                icon: "restart_alt"
                label: qsTr("Reiniciar")
                onClicked: Pomodoro.run("reset")
            }
        }
    }
}
