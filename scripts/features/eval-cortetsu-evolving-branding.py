#!/usr/bin/env python3
"""Product eval for contextual Evolving Mark semantics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
renderer = (ROOT / "cortetsu/components/CortetsuEvolvingMark.qml").read_text(encoding="utf-8")
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")
wallpaper = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")

checks = {
    "phase mapping is explicit": all(token in renderer for token in ("Human", "Awakening", "Monster", "Ascended", "Cosmic")),
    "idle is not Cosmic": 'phase: "Ascended"' in renderer and "cosmicDefault" not in renderer,
    "BottomHub uses real intent": all(token in mode for token in ('"Monster"', '"Awakening"', '"Human"', "pressed", "activeFocus")),
    "wallpaper waits for acknowledgement": all(token in wallpaper for token in ("pendingApplyPath", "onActualCurrentChanged", "cosmicPulseTimer.restart()")),
    "Cosmic is short and rare": all(token in wallpaper for token in ("cosmicPulse", "? \"Cosmic\"", "interval: CortetsuDesign.motionDeliberateMs")),
    "wallpaper settled selection ascends": all(token in wallpaper for token in ("applying || animating || applyFailed", "? \"Ascended\"")),
    "renderer has no input ownership": all(token not in renderer for token in ("MouseArea", "Keys.", "Window")),
    "fixed geometry": all(token in renderer for token in ("implicitWidth: 64", "implicitHeight: 64", "width: implicitWidth", "height: implicitHeight")),
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu Evolving Mark product eval: {sum(checks.values())}/{len(checks)}")
