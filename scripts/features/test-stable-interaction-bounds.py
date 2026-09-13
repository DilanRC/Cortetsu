#!/usr/bin/env python3
"""Regression guard for stable hitboxes across first-party dense controls."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
row = (ROOT / "cortetsu/components/CortetsuListRow.qml").read_text(encoding="utf-8")
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text(encoding="utf-8")
rail = (ROOT / "cortetsu/modules/CortetsuAppRail.qml").read_text(encoding="utf-8")
utilities = (ROOT / "cortetsu/modules/utilities/Content.qml").read_text(encoding="utf-8")
battery = (ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml").read_text(encoding="utf-8")

assert "scale: 1" in button
assert "property real visualScale" in row
assert "scale: root.visualScale" in row
assert "scale: 1" in row
assert "scale: appMouse" not in rail
assert "hovered: appMouse.containsMouse" in rail
assert "scale: 1" in utilities
assert "hovered: actionLayer.containsMouse" in utilities
assert "pressed: actionLayer.pressed" in utilities
assert "scale: 1" in battery
assert "hovered: stateLayer.containsMouse" in battery
assert "pressed: stateLayer.pressed" in battery

print("PASS: dense first-party controls keep stable pointer bounds")
