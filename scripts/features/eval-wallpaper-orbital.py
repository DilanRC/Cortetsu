#!/usr/bin/env python3
"""Product eval for perceptible first-party wallpaper orbital motion."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
orbit = (ROOT / "cortetsu/modules/wallpaper/OrbitModel.js").read_text(encoding="utf-8")

contracts = {
    "stable orbit model during transition": "Orbit.satellites(filteredEntries, windowIndex, windowIndex, visibleLimit)" in content,
    "animated accumulated phase": "orbitMotion.to = orbitPhase - steps * Orbit.angularStep" in content,
    "motion duration": "duration: 220" in content,
    "continuous trigonometric geometry": all(token in content for token in ("Math.cos(angle)", "Math.sin(angle)", "property real orbitPhase")),
    "depth hierarchy": all(token in content for token in ("scale: satellite.visualScale", "opacity: satellite.hovered ?", "z: 2 + Math.round(depth * 8)")),
    "satellite hitbox stays stable": "scale: 1" in content and "MouseArea" in content,
    "selection state": all(token in content for token in ("currentStateLabel", "currentIsApplied", "heroStateText")),
    "first-party manager header": all(token in content for token in ("Wallpaper Forge", "Wallpaper-aware desktop surface", "cortetsu-mark.svg", 'icon: "close"')),
    "keyboard navigation": all(token in content for token in ("Qt.Key_Left", "Qt.Key_Right", "Qt.Key_Return", "Qt.Key_Escape")),
    "angle contract": all(token in orbit for token in ("function angularStep", "function satelliteAngle", "Math.PI * 2")),
}

assert all(contracts.values()), [name for name, passed in contracts.items() if not passed]
print(f"Wallpaper orbital product eval: {sum(contracts.values())}/{len(contracts)}")
