#!/usr/bin/env python3
"""Small product eval for full-surface ownership and escape semantics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
checks = {
    "all retained content is first-party hosted": all(name in source for name in (
        "Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper",
        "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper",
    )),
    "host follows active-screen state": "CortetsuShellState.forActive()" in source,
    "escape closes the retained group": "closeRetainedOverlays()" in source,
    "full surfaces own overlay layer": "WlrLayer.Overlay" in source,
}
for label, passed in checks.items():
    if not passed:
        raise SystemExit(f"FAIL: {label}")
print(f"Retained surfaces host eval: {sum(checks.values())}/{len(checks)} (100%)")
