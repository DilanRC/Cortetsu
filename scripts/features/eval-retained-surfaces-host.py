#!/usr/bin/env python3
"""Small product eval for full-surface ownership and escape semantics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
drawers = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
checks = {
    "all retained content is first-party hosted": all(name in source for name in (
        "Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper",
        "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper",
    )),
    "host follows monitor-local state": all(marker in source for marker in (
        "model: CortetsuScreens.screens",
        "required property ShellScreen modelData",
        "CortetsuShellState.forScreen(modelData)",
        "screen: modelData",
    )) and "CortetsuShellState.forActive()" not in source,
    "escape closes the retained group": "closeRetainedOverlays()" in source,
    "full surfaces own overlay layer": "WlrLayer.Overlay" in source,
    "drawer resolves bar through explicit import boundary": 'import "../bar" as Bar' in drawers and "Bar.BarWrapper {" in drawers,
}
for label, passed in checks.items():
    if not passed:
        raise SystemExit(f"FAIL: {label}")
print(f"Retained surfaces host eval: {sum(checks.values())}/{len(checks)} (100%)")
