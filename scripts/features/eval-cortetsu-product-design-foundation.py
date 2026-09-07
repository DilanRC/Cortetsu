from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
design = (ROOT / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
assert all(token in design for token in ("colorSumi", "colorTetsu", "colorWashi", "colorIndigo", "colorVermillion"))
assert "var colorSuccess" in design
assert "var colorIndigo" in design
assert "var radiusSurface = 28" in design
assert "var spacingSection = 32" in design
assert "var motionPanelMs = 240" in design
print("PASS: product foundation eval preserves Cortetsu semantic palette and scale")
