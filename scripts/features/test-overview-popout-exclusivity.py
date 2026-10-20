#!/usr/bin/env python3
"""Regression gate: Overview must close visible bar popouts before opening."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/OverviewController.qml").read_text()

assert "function closeAllPopouts()" in source
assert "CortetsuShellState.componentsFor(screen)?.popouts" in source
assert "popouts.close();" in source
open_body = source.split("function open(): void", 1)[1].split("function close(): void", 1)[0]
assert open_body.index("closeAllPopouts();") < open_body.index("OverlayPolicy.open(CortetsuShellState.allStates(), state, \"overview\");")

print("PASS: Overview closes all first-party popouts before opening")
