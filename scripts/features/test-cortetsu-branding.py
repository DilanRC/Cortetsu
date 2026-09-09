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
assert canonical.count("<path") == 6
assert all(colour in canonical for colour in ("#F6F3EC", "#77C8FF", "#FF8A3D"))
assert "forged C" in canonical and "star core" in canonical

# Surface variants follow product tokens instead of the discarded forge palette.
assert all(colour in dark for colour in ("#1D2128", "#77C8FF", "#FF8A3D", "#F6F3EC"))
assert all(colour in light for colour in ("#F6F3EC", "#77C8FF", "#FF8A3D"))
assert all(colour in app for colour in ("#0D1118", "#1D2128", "#F6F3EC", "#FF8A3D"))
for legacy in ("#E7E0D5", "#526D82", "#0B0D10", "angular open C", "chamfered steel T"):
    assert legacy not in canonical + dark + light + readme, legacy

assert manifest["name"] == "Cortetsu Branding Suite"
assert manifest["concept"] == "forged C + star core"
assert manifest["palette"]["ember_orange"] == "#FF8A3D"
assert manifest["rules"]["dangerColourDecorative"] is False
assert manifest["rules"]["successColourDecorative"] is False

# The shell itself uses Cortetsu identity, not a distro badge.
assert 'Quickshell.shellPath("assets/branding/cortetsu-mark.svg")' in mode
assert "/usr/share/icons/cachyos.svg" not in mode

print("PASS: Cortetsu branding uses the CT identity and product-semantic palette")
