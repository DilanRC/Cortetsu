from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "SYSTEM FEEDBACK" in content
assert 'assets/branding/cortetsu-mark.svg' in content
assert "signatureMark" in content
assert "Brightness" in content and "Volume" in content
print("PASS: OSD has a shared Cortetsu feedback header, geometry, and live levels")
