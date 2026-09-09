from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
design = (ROOT / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
brand = ROOT / "cortetsu/assets/branding/cortetsu-mark-ascended.svg"
doc = ROOT / "docs/design/CORTETSU-PRODUCT-REBUILD.md"

assert brand.is_file(), "Cortetsu mark is missing"
svg = brand.read_text(encoding="utf-8")
assert "data:image/png;base64" in svg
assert "Evolving Mark" in svg and "Ascended" in svg
assert "Caelestia" not in svg
for name, value in (("spacingUnit", 4), ("spacingCompact", 8), ("spacingStandard", 12),
                    ("spacingComfortable", 16), ("spacingSpacious", 24), ("spacingSection", 32),
                    ("radiusSmall", 8), ("radiusMedium", 12), ("radiusLarge", 20), ("radiusSurface", 28),
                    ("controlHeightPrimary", 40), ("motionFastMs", 120),
                    ("motionStandardMs", 180), ("motionDeliberateMs", 240)):
    assert re.search(rf"var {name} = {value}(?:\D|$)", design), f"missing design token {name}={value}"
assert doc.is_file() and "Product Rebuild" in doc.read_text(encoding="utf-8")
print("PASS: Cortetsu product foundation defines brand mark, tokens, motion, and design record")
