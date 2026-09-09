#!/usr/bin/env python3
"""Product eval for wallpaper-aware colour state without brand fallback loss."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
colours = (ROOT / "cortetsu/services/CortetsuColours.qml").read_text(encoding="utf-8")
wallpapers = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")

criteria = {
    "current scheme readback": "schemePath" in colours and "onFileChanged: root.load(text(), false)" in colours,
    "validated hex boundary": "normaliseHex" in colours and "#[0-9a-fA-F]{6}" in colours,
    "reactive active palette": "readonly property var activeColours:" in colours and "root.schemeColour(" in colours,
    "brand fallback": all(token in colours for token in ("CortetsuDesign.colorPrimary", "CortetsuDesign.colorSurface", "CortetsuDesign.colorWashi")),
    "danger semantic stable": "m3error: CortetsuDesign.colorVermillion" in colours,
    "contrast fallback": all(token in colours for token in ("CortetsuDesign.colorWashi", "CortetsuDesign.colorTetsu")),
    "wall luminance": "readonly property real wallLuminance:" in colours and "function luminance" in colours,
    "preview bridge": "CortetsuColours.load(text, true);" in wallpapers,
    "preview reset": "CortetsuColours.clearPreview();" in wallpapers and "function clearPreview(): void" in colours,
    "smart scheme gate": "if (CortetsuConfig.smartScheme)" in wallpapers,
}

missing = [name for name, passed in criteria.items() if not passed]
print(f"Wallpaper palette eval: {len(criteria) - len(missing)}/{len(criteria)}")
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
