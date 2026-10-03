#!/usr/bin/env python3
"""Product eval for perceptible first-party wallpaper orbital motion."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
orbit = (ROOT / "cortetsu/modules/wallpaper/OrbitModel.js").read_text(encoding="utf-8")

contracts = {
    "stable orbit model during transition": "Orbit.arc(filteredEntries, windowIndex, arcHalf + 1)" in content,
    "turn animates in slots and re-anchors": "orbitMotion.to = steps;" in content and "root.windowIndex = root.currentIndex;\n            root.orbitPhase = 0;" in content,
    "motion duration": "duration: CortetsuDesign.wallUtilityOrbitMotionMs" in content,
    "continuous trigonometric geometry": all(token in content for token in ("Math.cos(angle)", "Math.sin(angle)", "property real orbitPhase")),
    "depth hierarchy": all(token in content for token in ("scale: satellite.visualScale", "opacity: satellite.hovered ?", "z: 2 + Math.round(depth * 8)", "visible: depth > 0")),
    "satellite hitbox stays stable": "scale: 1" in content and "MouseArea" in content,
    "selection state": all(token in content for token in ("currentStateLabel", "currentIsApplied", "currentFailed", "WallpaperStage {")),
    "first-party manager header": all(token in content for token in ("Wallpaper Orbital", "CortetsuSearchBar", "CortetsuEvolvingMark", "markPhase", 'icon: "close"')),
    "keyboard navigation": all(token in content for token in ("Qt.Key_Left", "Qt.Key_Right", "Qt.Key_Up", "Qt.Key_Down", "Qt.Key_Home", "Qt.Key_End", "Qt.Key_PageUp", "Qt.Key_PageDown", "Qt.Key_Tab", "Qt.Key_Slash", "Qt.Key_R", "Qt.Key_Return", "Qt.Key_Escape")),
    "stage keeps the wallpaper proportion": "height: width * 9 / 16" in content and "parent.height * 16 / 9" in content,
    "browse states": all(token in content for token in ("libraryEmpty", "noResults", "gridMode", "GridView {", 'qsTr("Reintentar")', "CortetsuWallpapers.scanning")),
    "angle contract": all(token in orbit for token in ("function arc(", "function arcAngle", "function arcDepth", "function arcSteps")),
}

assert all(contracts.values()), [name for name, passed in contracts.items() if not passed]
print(f"Wallpaper orbital product eval: {sum(contracts.values())}/{len(contracts)}")
