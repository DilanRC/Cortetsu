#!/usr/bin/env python3
"""Static product-identity contract for Cortetsu branding assets."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
branding = ROOT / "cortetsu/assets/branding"

canonical = (branding / "cortetsu-mark-ascended.svg").read_text(encoding="utf-8")
dark = (branding / "cortetsu-mark-dark.svg").read_text(encoding="utf-8")
light = (branding / "cortetsu-mark-light.svg").read_text(encoding="utf-8")
app = (branding / "cortetsu-app-icon.svg").read_text(encoding="utf-8")
readme = (branding / "README.md").read_text(encoding="utf-8")
manifest = json.loads((branding / "manifest.json").read_text(encoding="utf-8"))
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")
renderer = (ROOT / "cortetsu/components/CortetsuEvolvingMark.qml").read_text(encoding="utf-8")

for asset in (
    "cortetsu-mark.svg", "cortetsu-mark-human.svg", "cortetsu-mark-awakening.svg",
    "cortetsu-mark-monster.svg", "cortetsu-mark-ascended.svg", "cortetsu-mark-cosmic.svg",
    "cortetsu-mark-dark.svg", "cortetsu-mark-light.svg",
    "cortetsu-mark-monochrome-black.svg", "cortetsu-mark-monochrome-white.svg",
    "cortetsu-app-icon.svg", "cortetsu-lockup-dark.svg", "cortetsu-lockup-light.svg",
):
    assert (branding / asset).is_file(), asset

assert "data:image/png;base64" in canonical
assert "Cortetsu Evolving Mark" in readme
assert all(phase in renderer for phase in ("Human", "Awakening", "Monster", "Ascended", "Cosmic"))
assert "cortetsu-mark-${phaseKey.toLowerCase()}.svg" in renderer
assert manifest["name"] == "Cortetsu Evolving Mark"
assert manifest["concept"] == "transformation under pressure"
assert manifest["canonical"] == "cortetsu-mark-ascended.svg"
assert manifest["rules"]["cosmicDefault"] is False
assert manifest["rules"]["brandAccentIsPrivate"] is True
assert manifest["rules"]["dangerColourDecorative"] is False
assert manifest["rules"]["successColourDecorative"] is False

# The shell itself uses Cortetsu identity, not a distro badge.
assert 'evolvingMarkPhase:' in mode
assert '"Monster"' in mode and '"Awakening"' in mode and '"Human"' in mode
assert "/usr/share/icons/cachyos.svg" not in mode
assert "MouseArea" not in renderer
assert "Window" not in renderer

print("PASS: Cortetsu branding uses the CT identity and product-semantic palette")
