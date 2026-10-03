#!/usr/bin/env python3
"""Static contract check for the first controller migration."""
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
source = (repo / "cortetsu/modules/CalendarController.qml").read_text(encoding="utf-8")

assert "CortetsuShellState.forScreen(screen)?.cortetsuState?.calendar" in source
assert 'state.setRetained("calendar", false)' in source
assert "CortetsuShellState.forActive()?.cortetsuState" in source
assert "OverlayPolicy.closeOtherPanels(state)" in source
assert 'state.setRetained("calendar", true)' in source
assert "CortetsuShellState.forScreen(screen)?.calendar" not in source
print("PASS: CalendarController uses CortetsuScreenState")
