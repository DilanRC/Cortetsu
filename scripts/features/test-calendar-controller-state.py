#!/usr/bin/env python3
"""Static contract of the Calendar controller: the shared retained-surface
controller on CortetsuScreenState and CortetsuOverlayPolicy (O-1: it used to
close other panels only on its own screen)."""
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
source = (repo / "cortetsu/modules/CalendarController.qml").read_text(encoding="utf-8")
shared = (repo / "cortetsu/modules/RetainedSurfaceController.qml").read_text(encoding="utf-8")

assert "RetainedSurfaceController {" in source
for marker in ('surfaceKey: "calendar"', 'ipcTarget: "calendar"', 'shortcutName: "calendar"'):
    assert marker in source, marker
assert 'import "CortetsuOverlayPolicy.js" as OverlayPolicy' in shared
for marker in ("OverlayPolicy.open(CortetsuShellState.allStates(), target, root.surfaceKey)",
               "OverlayPolicy.close(CortetsuShellState.allStates(), root.surfaceKey)",
               "OverlayPolicy.openAnywhere(CortetsuShellState.allStates(), root.surfaceKey)"):
    assert marker in shared, marker
assert "closeOtherPanels" not in source + shared, "exclusivity lives in the policy, across screens"
assert "CortetsuShellState.forScreen(screen)?.calendar" not in source + shared
print("PASS: CalendarController is the shared retained-surface controller on the overlay policy")
