#!/usr/bin/env python3
"""Small deterministic eval for the shared stable-hitbox design contract."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
row = (ROOT / "cortetsu/components/CortetsuListRow.qml").read_text(encoding="utf-8")
rail = (ROOT / "cortetsu/modules/CortetsuAppRail.qml").read_text(encoding="utf-8")
utilities = (ROOT / "cortetsu/modules/utilities/Content.qml").read_text(encoding="utf-8")
battery = (ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml").read_text(encoding="utf-8")

criteria = {
    "list rows transform painted content": "scale: root.visualScale" in row and "scale: 1" in row,
    "app rail paints hover without root transform": "hovered: appMouse.containsMouse" in rail and "scale: appMouse" not in rail,
    "utility actions expose shared hover press": all(x in utilities for x in ("hovered: actionLayer.containsMouse", "pressed: actionLayer.pressed")),
    "battery profiles expose shared hover press": all(x in battery for x in ("hovered: stateLayer.containsMouse", "pressed: stateLayer.pressed")),
}

failed = [name for name, passed in criteria.items() if not passed]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))

print(f"Stable interaction bounds eval: {len(criteria)}/{len(criteria)} (100%)")
