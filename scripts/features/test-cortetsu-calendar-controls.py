#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = "".join((ROOT / "cortetsu/modules/calendar" / name).read_text(encoding="utf-8")
                  for name in ("Content.qml", "PomodoroCard.qml"))

assert "CortetsuButton" in content
assert "component FocusButton" not in content
assert "import QtQuick.Controls" not in content
for marker in (
    'icon: CalendarService.syncing ? "sync" : "refresh"',
    'icon: "chevron_left"',
    'icon: "chevron_right"',
    'icon: "today"',
    'icon: "skip_next"',
    'icon: "restart_alt"',
    'onClicked: root.screenState.cortetsuState?.setRetained("calendar", false)',
):
    assert marker in content, marker

print("PASS: Calendar header, navigation and Pomodoro actions use the shared CortetsuButton interaction contract")
