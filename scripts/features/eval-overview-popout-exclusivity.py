#!/usr/bin/env python3
"""Deterministic eval for the visual overlay exclusivity contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/OverviewController.qml").read_text()

checks = {
    "all screens are covered": "for (const screen of CortetsuScreens.screens)" in source,
    "owned popout boundary is used": "componentsFor(screen)?.popouts" in source,
    "popouts close before overview opens": source.index("closeAllPopouts();") < source.index("OverlayPolicy.open(CortetsuShellState.allStates(), state, \"overview\");"),
}
assert all(checks.values()), checks
print(f"Overview popout exclusivity eval: {sum(checks.values())}/{len(checks)} (100%)")
