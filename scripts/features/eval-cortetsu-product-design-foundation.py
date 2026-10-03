from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
design = (ROOT / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
brand = (ROOT / "cortetsu/assets/branding/cortetsu-mark-ascended.svg").read_text(encoding="utf-8")
manifest = (ROOT / "cortetsu/assets/branding/manifest.json").read_text(encoding="utf-8")
assert all(token in design for token in ("colorSumi", "colorTetsu", "colorWashi", "colorIndigo", "colorVermillion"))
assert "var colorSuccess" in design
assert "var colorIndigo" in design
assert "var radiusSurface = 28" in design
assert "var spacingSection = 32" in design
assert "var motionPanelMs = 240" in design
assert "Evolving Mark" in brand and "Ascended" in brand
assert "data:image/png;base64" in brand
assert '"concept": "transformation under pressure"' in manifest
print("PASS: product foundation eval preserves Cortetsu semantic palette and scale")
