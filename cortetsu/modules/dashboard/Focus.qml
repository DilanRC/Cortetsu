pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import ".."
import "../../theme"
import "../pomodoro"
import "../CortetsuTypography.js" as CortetsuTypography
import "../pomodoro/PomodoroModel.js" as Model

Item {
    id: root

    required property var screenState
    // Pomodoro service (one per shell) and the helper own the state and every
    // transition; this card used to keep its own copy of both and re-read the
    // state file without reloading it.
    readonly property var pomodoro: Pomodoro.state
    property double nowMs: Date.now()
    readonly property string command: Model.primaryCommand(pomodoro)
    readonly property string actionLabel: command === "resume" ? qsTr("Reanudar") : command === "pause" ? qsTr("Pausar") : qsTr("Iniciar")
    readonly property string actionIcon: command === "pause" ? "pause" : "play_arrow"

    function phaseLabel(): string {
        if (pomodoro.phase === "FOCUS")
            return qsTr("Sesión de concentración");
        if (pomodoro.phase === "BREAK")
            return qsTr("Descanso corto");
        if (pomodoro.phase === "LONG_BREAK")
            return qsTr("Descanso largo");
        if (pomodoro.phase === "PAUSED")
            return qsTr("En pausa");
        return qsTr("Listo para concentrarse");
    }

    function sessionsLabel(count: int): string {
        return count === 1 ? qsTr("1 sesión") : qsTr("%1 sesiones").arg(count);
    }

    onPomodoroChanged: nowMs = Date.now()

    SystemClock {
        enabled: (root.screenState?.dashboard ?? false) && Pomodoro.running
        precision: SystemClock.Seconds
        onDateChanged: root.nowMs = Date.now()
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
                text: qsTr("CONCENTRACIÓN")
                textSize: CortetsuTypography.labelSmallPx
                color: CortetsuDesign.colorPrimary
                font.weight: Font.DemiBold
            }

            Item { Layout.fillWidth: true }

            CortetsuText {
                text: root.sessionsLabel(Number(root.pomodoro.completedSessions || 0))
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
                    text: Model.timeLeft(root.pomodoro, root.nowMs)
                    textSize: CortetsuTypography.displayClockPx
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
                active: Pomodoro.running
                disabled: Pomodoro.busy
                onClicked: Pomodoro.run(root.command)
            }
        }

        CortetsuProgressBar {
            Layout.fillWidth: true
            value: Model.progress(root.pomodoro, root.nowMs)
            barHeight: 4
            barRadius: 2
            trackColor: Qt.alpha(CortetsuDesign.colorOutlineVariant, 0.28)
        }

        RowLayout {
            Layout.fillWidth: true
            visible: root.pomodoro.phase !== "IDLE" && root.pomodoro.phase !== undefined

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                icon: Model.isBreak(root.pomodoro.phase) ? "skip_next" : "restart_alt"
                label: Model.isBreak(root.pomodoro.phase) ? qsTr("Saltar") : qsTr("Reiniciar")
                disabled: Pomodoro.busy
                onClicked: Pomodoro.run(Model.isBreak(root.pomodoro.phase) ? "skip" : "reset")
            }
        }
    }
}
