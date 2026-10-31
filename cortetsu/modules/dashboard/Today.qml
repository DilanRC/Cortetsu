pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../components"
import ".."
import "../../theme"
import "../calendar"
import "../CortetsuTypography.js" as CortetsuTypography
import "../CortetsuOverlayPolicy.js" as OverlayPolicy
import "../calendar/CalendarModel.js" as CalendarModel

Item {
    id: root

    required property var screenState
    property date dayAnchor: new Date()

    // The cache and the date rules are the Calendar's own (CalendarService,
    // CalendarModel.js): this card used to keep a third copy of both, and
    // re-read the cache without reloading it.
    readonly property var todayEvents: CalendarModel.eventsOn(CalendarService.events, dayAnchor)
        .slice()
        .sort((a, b) => CalendarModel.eventStart(a).getTime() - CalendarModel.eventStart(b).getTime())

    function eventTime(event): string {
        if (event.allDay)
            return qsTr("Todo el día");
        const start = CalendarModel.eventStart(event);
        const end = new Date(event.end);
        if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()))
            return qsTr("Programado");
        return `${Qt.formatTime(start, "HH:mm")}–${Qt.formatTime(end, "HH:mm")}`;
    }

    // Same transition as the calendar shortcut; it closes this dashboard too.
    function openCalendar(): void {
        OverlayPolicy.open(CortetsuShellState.allStates(), screenState, "calendar");
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.screenState?.dashboard ?? false
        onTriggered: root.dayAnchor = new Date()
    }

    // A margin note, no card: the kanji for day, the label, the events.
    // Clipped, so nothing can ever spill over the note below.
    clip: true
    ColumnLayout {
        anchors.fill: parent
        spacing: CortetsuDesign.spacingCompact

        RowLayout {
            Layout.fillWidth: true
            spacing: CortetsuDesign.spacingCompact

            Text {
                text: "日"
                font.family: CortetsuTypography.kanjiFamily
                font.pixelSize: CortetsuTypography.labelLargePx
                color: CortetsuDesign.colorIndicator
                opacity: 0.85
            }

            DashLabel { text: qsTr("HOY") }

            Item { Layout.fillWidth: true }

            CortetsuButton {
                compact: true
                icon: "calendar_month"
                label: ""
                tooltipText: qsTr("Abrir calendario")
                onClicked: root.openCalendar()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            Repeater {
                model: root.todayEvents.slice(0, 2)

                // One line per event, like a margin note: the time, then
                // the title. A list row is 52 px tall and two of them spilled
                // over the note below.
                delegate: Item {
                    id: event
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredHeight: eventLine.implicitHeight + 6

                    RowLayout {
                        id: eventLine
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: CortetsuDesign.spacingCompact

                        CortetsuText {
                            Layout.preferredWidth: 76
                            text: root.eventTime(event.modelData)
                            textSize: CortetsuTypography.labelSmallPx
                            color: CortetsuDesign.colorIndicator
                            font.features: { "tnum": 1 }
                        }
                        CortetsuText {
                            Layout.fillWidth: true
                            text: event.modelData.title || qsTr("Evento sin título")
                            textSize: CortetsuTypography.bodySmallPx
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openCalendar()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.todayEvents.length === 0

                RowLayout {
                    anchors.centerIn: parent
                    spacing: CortetsuDesign.spacingCompact

                    CortetsuIcon {
                        text: "event_available"
                        iconSize: CortetsuTypography.iconMediumPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }

                    CortetsuText {
                        text: qsTr("No hay eventos hoy")
                        textSize: CortetsuTypography.bodySmallPx
                        color: CortetsuDesign.colorOnSurfaceVariant
                    }
                }
            }
        }

        CortetsuText {
            Layout.fillWidth: true
            visible: root.todayEvents.length > 2
            text: qsTr("+%1 más en el calendario").arg(root.todayEvents.length - 2)
            textSize: CortetsuTypography.labelSmallPx
            color: CortetsuDesign.colorOnSurfaceVariant
            horizontalAlignment: Text.AlignRight
        }
    }
}
