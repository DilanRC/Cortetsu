#!/usr/bin/env python3
"""Gate contract for the approved five-phase Cortetsu identity."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
BRANDING = ROOT / "cortetsu/assets/branding"
PHASES = ("human", "awakening", "monster", "ascended", "cosmic")
manifest = json.loads((BRANDING / "manifest.json").read_text(encoding="utf-8"))
renderer = (ROOT / "cortetsu/components/CortetsuEvolvingMark.qml").read_text(encoding="utf-8")
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")
wallpaper = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
wallpaper_service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")

assert manifest["canonical"] == "cortetsu-mark-ascended.svg"
assert manifest["rules"]["cosmicDefault"] is False
assert manifest["rules"]["brandAccentIsPrivate"] is True
for phase in PHASES:
    asset = BRANDING / f"cortetsu-mark-{phase}.svg"
    text = asset.read_text(encoding="utf-8")
    assert asset.is_file() and "data:image/png;base64" in text, asset

assert "property string phase" in renderer
assert "normalizedPhase" in renderer
assert "phaseAssetPath" in renderer
assert "implicitWidth: 64" in renderer and "implicitHeight: 64" in renderer
assert "property bool animated" in renderer and "phaseTransition" in renderer
assert "property color accent" in renderer and "effectiveColor" in renderer
assert renderer.count("brightness: 1") == 2
for forbidden in ("MouseArea", "Window", "Overlay"):
    assert forbidden not in renderer, forbidden

assert 'evolvingMarkPhase:' in mode
assert '"Human"' in mode and '"Awakening"' in mode and '"Monster"' in mode
assert 'phase: root.markPhase' in wallpaper
assert 'monochrome: false' in wallpaper
assert 'accent: CortetsuColours.palette.m3primary' in wallpaper
assert 'pendingApplyPath' in wallpaper and 'cosmicPulse' in wallpaper
assert 'applyStatus === "applying" || animating' in wallpaper
assert 'applyStatus === "failed"' in wallpaper
assert '(currentIsApplied ? "Ascended" : "Human")' in wallpaper
assert 'currentPath' in wallpaper and '? "Ascended"' in wallpaper
assert 'function closeManager(): void { cancel(); }' in wallpaper
assert 'actualCurrent = path' not in wallpaper_service
assert 'onFileChanged:' in wallpaper_service and 'root.readActual(text())' in wallpaper_service

for old in ("forged C + star core", "forged C/star-core", "forged C"):
    for path in (BRANDING / "README.md", BRANDING / "manifest.json", ROOT / "docs/design/CORTETSU-PRODUCT-REBUILD.md"):
        assert old not in path.read_text(encoding="utf-8"), (old, path)

print("PASS: five approved phases, fixed renderer, semantic isolation and real apply acknowledgement are wired")
