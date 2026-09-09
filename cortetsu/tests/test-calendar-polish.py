#!/usr/bin/env python3
from pathlib import Path

content = (Path(__file__).resolve().parents[2] / "cortetsu/modules/calendar/Content.qml").read_text(encoding="utf-8")
for expected in (
    'calendar.primary ? qsTr("Personal")',
    'eventsForDay(dayCell.day).slice(0, 3)',
    'modelData.calendarColor || CortetsuDesign.colorTertiary',
    'label: qsTr("Skip break")',
    'root.runPomodoro("skip")',
    'text: qsTr("No events")',
    'text: qsTr("Take the time for yourself.")',
    'root.eventTime(modelData)',
    'modelData.location',
    'implicitWidth: chipRow.implicitWidth',
    'icon: "skip_next"',
    'icon: "restart_alt"',
    'onClicked: root.runPomodoro("reset")',
    'root.pomodoro = JSON.parse(text.trim())',
    'function runPomodoro(command: string)',
    'function onCalendarChanged()',
    'root.requestCalendarSync()',
    'root.requestCalendarSync(true)',
    'onFileChanged: pomodoroReload.restart()',
    'phase === "LONG_BREAK"',
    'qsTr("Long break")',
    'eventOccursOnDate',
):
    assert expected in content, expected
assert 'CortetsuTypography.titleLargePx' in content
assert 'CortetsuButton {' in content
assert 'component FocusButton' not in content
assert 'import QtQuick.Controls' not in content
assert 'Tokens.font.display.small' not in content
for legacy in ('Caelestia.Config', 'qs.components', 'Colours.', 'Tokens.', 'StyledRect', 'StyledText', 'MaterialIcon'):
    assert legacy not in content, legacy
assert "delegate: CheckBox" not in content
print("PASS: Calendar lifecycle sync, event design, and full Pomodoro phases are wired")
