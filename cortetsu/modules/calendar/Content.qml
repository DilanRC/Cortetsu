pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import ".."
import "../../components"
import "../../theme"
import "../CortetsuTypography.js" as CortetsuTypography
import "CalendarModel.js" as CalendarModel

// Calendar surface: month grid, agenda of the selected day and the Pomodoro
// card. Presentation only: the data and its sync live in CalendarService, the
// date logic in CalendarModel.js and Pomodoro in its own service. Escape is
// handled by RetainedSurfacesHost for every retained surface.
Item {
    id: root
    focus: true
    required property var screenState

    readonly property bool shown: screenState?.cortetsuState?.calendar ?? false
    property date selectedDate: new Date()
    // Start of the current day; follows midnight while the calendar is open.
    property date today: CalendarModel.dayStart(new Date())
    readonly property int year: selectedDate.getFullYear()
    readonly property int month: selectedDate.getMonth()
    readonly property var cells: CalendarModel.monthCells(year, month)
    readonly property var monthEvents: CalendarModel.eventsByDay(CalendarService.events, year, month)
    readonly property var selectedEvents: CalendarModel.eventsOn(CalendarService.events, selectedDate)

    function isToday(day: int): bool { return day > 0 && CalendarModel.sameDay(today, new Date(year, month, day)); }
    function isSelected(day: int): bool { return day > 0 && day === selectedDate.getDate(); }
    function friendlyName(calendar): string { return calendar.primary ? qsTr("Personal") : calendar.calendarName; }
    function eventTime(event): string {
        if (event.allDay) return qsTr("Todo el día");
        return `${Qt.formatTime(new Date(event.start), "HH:mm")}–${Qt.formatTime(new Date(event.end), "HH:mm")}`;
    }
    function eventCount(count: int): string { return count === 1 ? qsTr("1 evento") : qsTr("%1 eventos").arg(count); }
    function changeMonth(delta: int): void { selectedDate = new Date(year, month + delta, 1); }

    // Arrows move the selected day, PageUp/PageDown the month, Home goes to
    // today. Keys reach here from any control in the surface that does not
    // use them itself.
    readonly property var moveKeys: ({ left: Qt.Key_Left, right: Qt.Key_Right, up: Qt.Key_Up, down: Qt.Key_Down,
                                       pageUp: Qt.Key_PageUp, pageDown: Qt.Key_PageDown, home: Qt.Key_Home })
    Keys.onPressed: event => {
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
            return;
        const next = CalendarModel.dayForKey(event.key, selectedDate, today, moveKeys);
        if (next) {
            selectedDate = next;
            event.accepted = true;
        }
    }

    // Minute precision is enough to notice midnight; off while closed.
    SystemClock {
        enabled: root.shown
        precision: SystemClock.Minutes
        onDateChanged: root.today = CalendarModel.dayStart(date)
    }

    CortetsuSurface { outlined: false;
        anchors.fill: parent
        radius: CortetsuDesign.radiusLarge
        color: CortetsuDesign.colorSurface

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: CortetsuDesign.spacingComfortable
            spacing: CortetsuDesign.spacingStandard

            RowLayout {
                Layout.fillWidth: true
                CortetsuText { Layout.fillWidth: true; text: qsTr("Calendario"); textSize: CortetsuTypography.titleLargePx; color: CortetsuDesign.colorOnSurface }
                CortetsuText { visible: CalendarService.syncStatus.length > 0; text: CalendarService.syncStatus; textSize: CortetsuTypography.labelSmallPx; color: CortetsuDesign.colorOnSurfaceVariant }
                CortetsuButton { compact: true; icon: CalendarService.syncing ? "sync" : "refresh"; label: ""; tooltipText: qsTr("Sincronizar calendario"); disabled: CalendarService.syncing; onClicked: CalendarService.requestSync(true) }
                CortetsuButton { compact: true; icon: "close"; label: ""; tooltipText: qsTr("Cerrar calendario"); onClicked: root.screenState.cortetsuState?.setRetained("calendar", false) }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: CortetsuDesign.spacingComfortable

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 430
                    spacing: CortetsuDesign.spacingCompact

                    RowLayout {
                        Layout.fillWidth: true
                        CortetsuButton { compact: true; icon: "chevron_left"; label: ""; tooltipText: qsTr("Mes anterior"); onClicked: root.changeMonth(-1) }
                        CortetsuText { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: CortetsuRegional.formatDate(root.selectedDate, "monthYear", true); textSize: CortetsuTypography.titleMediumPx; color: CortetsuDesign.colorOnSurface }
                        CortetsuButton { compact: true; icon: "today"; label: qsTr("Hoy"); onClicked: root.selectedDate = root.today }
                        CortetsuButton { compact: true; icon: "chevron_right"; label: ""; tooltipText: qsTr("Mes siguiente"); onClicked: root.changeMonth(1) }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredHeight: 290
                        columns: 7
                        Repeater { model: [qsTr("Lu"), qsTr("Ma"), qsTr("Mi"), qsTr("Ju"), qsTr("Vi"), qsTr("Sá"), qsTr("Do")]; delegate: CortetsuText { required property var modelData; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; text: modelData; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx } }
                        Repeater {
                            model: 42
                            delegate: Item {
                                id: dayCell
                                required property int index
                                Layout.fillWidth: true; Layout.fillHeight: true
                                readonly property int day: root.cells[index]
                                readonly property var events: day ? root.monthEvents[day] ?? [] : []
                                // Selected: primary fill. Today: a neutral ring, so the two never
                                // read as the same blue (1.3:1 apart in the Cortetsu scheme).
                                Rectangle { objectName: "day-" + dayCell.day; anchors.centerIn: parent; width: 34; height: 34; radius: width / 2
                                    border.width: root.isToday(dayCell.day) && !root.isSelected(dayCell.day) ? 1 : 0
                                    border.color: CortetsuDesign.colorOnSurfaceVariant
                                    color: root.isSelected(dayCell.day) ? CortetsuDesign.colorPrimary : dayMouse.containsMouse ? Qt.alpha(CortetsuDesign.colorOnSurface, 0.08) : "transparent" }
                                CortetsuText { anchors.centerIn: parent; text: dayCell.day || ""; color: root.isSelected(dayCell.day) ? CortetsuDesign.colorOnPrimary : CortetsuDesign.colorOnSurface; font.weight: root.isToday(dayCell.day) ? Font.DemiBold : Font.Normal; textSize: CortetsuTypography.labelMediumPx }
                                Row {
                                    anchors.horizontalCenter: parent.horizontalCenter; anchors.bottom: parent.bottom; spacing: 2
                                    Repeater {
                                        model: dayCell.events.slice(0, 3)
                                        delegate: Rectangle { required property var modelData; width: 4; height: 4; radius: 2; color: modelData.calendarColor || CortetsuDesign.colorTertiary }
                                    }
                                    CortetsuText { visible: dayCell.events.length > 3; text: "+"; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                }
                                MouseArea { id: dayMouse; anchors.fill: parent; enabled: dayCell.day > 0; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.selectedDate = new Date(root.year, root.month, dayCell.day) }
                            }
                        }
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: CortetsuDesign.spacingCompact
                        Repeater {
                            model: CalendarService.calendars
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool chosen: CalendarService.enabledCalendars.includes(modelData.calendarId)
                                function toggle(): void { CalendarService.setCalendarEnabled(chip.modelData.calendarId, !chip.chosen); }
                                activeFocusOnTab: true
                                border.width: activeFocus ? 2 : 0
                                border.color: CortetsuDesign.colorIndicator
                                Keys.onSpacePressed: toggle()
                                Keys.onReturnPressed: toggle()
                                Keys.onEnterPressed: toggle()
                                Accessible.role: Accessible.CheckBox
                                Accessible.name: root.friendlyName(chip.modelData)
                                Accessible.checkable: true
                                Accessible.checked: chip.chosen
                                Accessible.onToggleAction: toggle()
                                Accessible.onPressAction: toggle()
                                implicitWidth: chipRow.implicitWidth + CortetsuDesign.spacingStandard * 2; implicitHeight: 30; radius: height / 2
                                color: chosen ? CortetsuDesign.colorSecondaryContainer : CortetsuDesign.colorSurfaceHigh
                                RowLayout {
                                    id: chipRow; anchors.centerIn: parent; spacing: CortetsuDesign.spacingCompact
                                    Rectangle { implicitWidth: 8; implicitHeight: 8; radius: 4; color: chip.modelData.calendarColor || CortetsuDesign.colorSecondary }
                                    CortetsuText { text: root.friendlyName(chip.modelData); color: chip.chosen ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                    CortetsuText { text: chip.chosen ? "✓" : "+"; color: chip.chosen ? CortetsuDesign.colorOnSecondaryContainer : CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelMediumPx }
                                }
                                MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: chip.toggle() }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 350
                    spacing: CortetsuDesign.spacingStandard

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: CortetsuDesign.radiusMedium
                        color: CortetsuDesign.colorSurfaceHigh
                        ColumnLayout {
                            anchors.fill: parent; anchors.margins: CortetsuDesign.spacingStandard; spacing: CortetsuDesign.spacingCompact
                            CortetsuText { Layout.fillWidth: true; objectName: "agendaTitle"; text: CortetsuRegional.formatDate(root.selectedDate, "longDay", true); textSize: CortetsuTypography.titleMediumPx; color: CortetsuDesign.colorOnSurface }
                            CortetsuText { text: root.selectedEvents.length ? root.eventCount(root.selectedEvents.length) : qsTr("Día libre"); color: CortetsuDesign.colorPrimary; textSize: CortetsuTypography.labelMediumPx }
                            ColumnLayout {
                                visible: !root.selectedEvents.length; Layout.fillWidth: true; Layout.fillHeight: true; spacing: CortetsuDesign.spacingCompact
                                Item { Layout.fillHeight: true }
                                CortetsuIcon { Layout.alignment: Qt.AlignHCenter; text: "event_available"; color: CortetsuDesign.colorOnSurfaceVariant; iconSize: CortetsuTypography.iconLargePx }
                                CortetsuText { Layout.alignment: Qt.AlignHCenter; text: qsTr("No hay eventos"); color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.titleSmallPx }
                                Item { Layout.fillHeight: true }
                            }
                            ListView {
                                id: agenda
                                visible: root.selectedEvents.length > 0; Layout.fillWidth: true; Layout.fillHeight: true; clip: true; spacing: CortetsuDesign.spacingCompact; model: root.selectedEvents
                                delegate: RowLayout {
                                    required property var modelData; width: agenda.width; spacing: CortetsuDesign.spacingCompact
                                    Rectangle { implicitWidth: 5; implicitHeight: eventDetails.implicitHeight; radius: 3; color: modelData.calendarColor || CortetsuDesign.colorPrimary }
                                    ColumnLayout {
                                        id: eventDetails; Layout.fillWidth: true; spacing: 1
                                        CortetsuText { Layout.fillWidth: true; text: modelData.title; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurface; textSize: CortetsuTypography.bodyLargePx }
                                        CortetsuText { Layout.fillWidth: true; text: `${root.eventTime(modelData)}  ·  ${root.friendlyName(modelData)}`; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                        CortetsuText { visible: !!modelData.location; Layout.fillWidth: true; text: modelData.location; elide: Text.ElideRight; color: CortetsuDesign.colorOnSurfaceVariant; textSize: CortetsuTypography.labelSmallPx }
                                    }
                                }
                            }
                        }
                    }

                    PomodoroCard {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 154
                    }
                }
            }
        }
    }
}
