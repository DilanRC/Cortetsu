#!/usr/bin/env python3
"""Product eval for Overview depth cues without moving card hitboxes."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
card = (ROOT / "cortetsu/modules/overview/WindowCard.qml").read_text(encoding="utf-8")

criteria = {
    "card root remains stable": "scale: 1" in card and "property real visualScale" in card,
    "painted card layers receive depth": card.count("scale: root.visualScale") >= 3,
    "depth uses shared motion token": "Behavior on visualScale" in card and "duration: CortetsuDesign.motionFastMs" in card,
    "pointer remains on root": "anchors.fill: parent" in card and "id: pointer" in card,
}

failed = [name for name, passed in criteria.items() if not passed]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))

print(f"Overview spatial bounds eval: {len(criteria)}/{len(criteria)} (100%)")
