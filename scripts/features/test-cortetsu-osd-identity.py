from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "ESTADO DEL SISTEMA" in content
assert "CortetsuEvolvingMark" in content
assert 'phase: "Ascended"' in content
assert "animated: false" in content
assert "signatureMark" in content
assert "Brillo" in content and "Volumen" in content
print("PASS: OSD has a shared Cortetsu feedback header, geometry, and live levels")
