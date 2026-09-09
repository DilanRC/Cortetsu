#!/usr/bin/env python3
"""Gate the dedicated first-party host for full retained surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
wallpaper = (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml").read_text(encoding="utf-8")

assert 'name: "retained-surfaces"' in host
assert "Variants {" in host
assert "model: CortetsuScreens.screens" in host
assert "required property ShellScreen modelData" in host
assert "CortetsuShellState.forScreen(modelData)" in host
assert "screen: modelData" in host
assert "CortetsuShellState.forActive()" not in host
assert "WlrLayershell.layer: WlrLayer.Overlay" in host
assert "WlrLayershell.keyboardFocus: surfaceOpen ? WlrKeyboardFocus.OnDemand" in host
for wrapper in ("Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper", "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper"):
    assert wrapper in host, wrapper
assert all(f"{wrapper} {{ id:" in panels for wrapper in (
    "Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper",
    "Display.Wrapper", "Wallpaper.Wrapper",
))
assert "id: calendar" in panels
assert "opacity: shouldBeActive ? 1 : 0" in wallpaper
assert "Content.qml owns the honest empty state" in wallpaper
print("PASS: retained surfaces have monitor-local independent overlay ownership and compatibility handles remain present")
