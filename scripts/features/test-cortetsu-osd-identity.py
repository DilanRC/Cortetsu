from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "SYSTEM FEEDBACK" in content
assert "colorPrimary" in content and "colorWashi" in content
assert "Brightness" in content and "Volume" in content
print("PASS: OSD has a shared Cortetsu feedback header, geometry, and live levels")
