#!/usr/bin/env python3
"""Calendar surface: design markers, lifecycle wiring and module boundaries.

The behaviour is tested by the QML engine (tests/qml/calendar, tests/qml/pomodoro)
and by test-calendar-pomodoro-services.py; this gate keeps the structure:
presentation in Content.qml and PomodoroCard.qml, data in CalendarService,
date rules in CalendarModel.js, Pomodoro transitions in the helper only.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[2] / "cortetsu/modules"
content = (root / "calendar/Content.qml").read_text(encoding="utf-8")
card = (root / "calendar/PomodoroCard.qml").read_text(encoding="utf-8")
service = (root / "calendar/CalendarService.qml").read_text(encoding="utf-8")
model = (root / "calendar/CalendarModel.js").read_text(encoding="utf-8")
pomodoro = (root / "pomodoro/Pomodoro.qml").read_text(encoding="utf-8")
view = content + card

for expected in (
    'calendar.primary ? qsTr("Personal")',
    'dayCell.events.slice(0, 3)',
    'modelData.calendarColor || CortetsuDesign.colorTertiary',
    'label: qsTr("Saltar descanso")',
    'Pomodoro.run("skip")',
    'text: qsTr("No hay eventos")',
    'text: qsTr("Tómate el tiempo para ti.")',
    'root.eventTime(modelData)',
    'modelData.location',
    'implicitWidth: chipRow.implicitWidth',
    'icon: "skip_next"',
    'icon: "restart_alt"',
    'Pomodoro.run("reset")',
    'qsTr("Descanso largo")',
    'CalendarModel.eventsOn(CalendarService.events, selectedDate)',
    'CalendarModel.eventsByDay(CalendarService.events, year, month)',
    'CalendarService.requestSync(true)',
    'precision: SystemClock.Minutes',
    'PomodoroCard {',
):
    assert expected in view, expected
assert 'CortetsuTypography.titleLargePx' in content
assert 'CortetsuButton {' in view
assert 'component FocusButton' not in view
assert 'import QtQuick.Controls' not in view
assert 'Tokens.font.display.small' not in view
for legacy in ('Caelestia.Config', 'qs.components', 'Colours.', 'Tokens.', 'StyledRect', 'StyledText', 'MaterialIcon'):
    assert legacy not in view, legacy
assert "delegate: CheckBox" not in view

# Interface text is Spanish, like the rest of the shell.
for english in ('"Calendar"', '"Today"', '"Sync calendar"', '"Close Calendar"', '"Your day is clear"',
                '"Take the time for yourself."', '"Syncing…"', '"Sync failed"', '"%1 sessions"', '"event"', '"Mo"'):
    assert english not in view + service, english

# Boundaries: the view keeps no data, process or file of its own; the date
# rules exist once; the card never recomputes a Pomodoro transition.
for owned in ("FileView", "Process {", "JSON.parse", "cortetsu-calendar", "cortetsu-pomodoro", "Keys.onEscapePressed"):
    assert owned not in view, owned
assert "function eventOccursOnDate" not in content and "function occursOn" in model
assert "targetEndTimestamp =" not in view + pomodoro, "the helper owns every Pomodoro transition"
assert "function runPomodoro" not in view

# Files are re-read when they change: FileView does not reload by itself.
assert service.count("onFileChanged: reload()") == 2  # event cache, calendar selection
assert pomodoro.count("onFileChanged: reload()") == 2  # state, announcements
assert "onOpenChanged: if (open) requestSync(false)" in service
assert "// startup inventory: cortetsu:calendar-sync" in service
assert "// startup inventory: cortetsu:pomodoro" in pomodoro
print("PASS: Calendar view, services and Pomodoro card keep their design and boundaries")
