#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/SessionHost.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
for marker in ('name: "session"', "WlrLayer.Overlay", "WlrKeyboardFocus.Exclusive", "CortetsuShellState.forScreen(modelData)", "Session.Content"):
    assert marker in host, marker
assert "CortetsuShellState.forActive()" not in host
assert "SessionHost {}" in shell
assert "id: session" in panels and "visible: false" in panels
assert "id: sessionWrapper\n        visible: false" in panels
print("PASS: session is a monitor-local first-party focused surface and the legacy panel is hidden")
