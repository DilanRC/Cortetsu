#!/usr/bin/env python3
"""Static product-identity contract for Cortetsu branding assets."""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[2]
branding = ROOT / "cortetsu/assets/branding"

canonical = (branding / "cortetsu-mark.svg").read_text(encoding="utf-8")
dark = (branding / "cortetsu-mark-dark.svg").read_text(encoding="utf-8")
light = (branding / "cortetsu-mark-light.svg").read_text(encoding="utf-8")
app = (branding / "cortetsu-app-icon.svg").read_text(encoding="utf-8")
readme = (branding / "README.md").read_text(encoding="utf-8")
manifest = json.loads((branding / "manifest.json").read_text(encoding="utf-8"))
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")

for asset in (
    "cortetsu-mark.svg", "cortetsu-mark-dark.svg", "cortetsu-mark-light.svg",
    "cortetsu-mark-monochrome-black.svg", "cortetsu-mark-monochrome-white.svg",
    "cortetsu-app-icon.svg", "cortetsu-lockup-dark.svg", "cortetsu-lockup-light.svg",
):
    assert (branding / asset).is_file(), asset

# Canonical mark is transparent and deliberately simple enough to survive 24px shell use.
assert '<rect' not in canonical
assert canonical.count("<path") == 3
assert "#E7E0D5" in canonical and "#526D82" in canonical
assert "Angular open C" in canonical

# Surface variants follow product tokens instead of the discarded forge palette.
assert "#E7E0D5" in dark and "#526D82" in dark
assert "#0B0D10" in light and "#334E68" in light
assert "#0B0D10" in app and "#E7E0D5" in app and "#526D82" in app
for legacy in ("#FF8A3D", "#77C8FF", "#1D2128", "ember", "Forge"):
    assert legacy not in canonical + dark + light + readme, legacy

assert manifest["name"] == "Cortetsu"
assert manifest["concept"] == "angular open C + chamfered steel T"
assert manifest["rules"]["dangerColourDecorative"] is False
assert manifest["rules"]["successColourDecorative"] is False

# The shell itself uses Cortetsu identity, not a distro badge.
assert 'Quickshell.shellPath("assets/branding/cortetsu-mark.svg")' in mode
assert "/usr/share/icons/cachyos.svg" not in mode

print("PASS: Cortetsu branding uses the CT identity and product-semantic palette")
