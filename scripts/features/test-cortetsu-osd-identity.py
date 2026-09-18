from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
qsd = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
assert 'import "../qsd" as FullOsd' in content
assert "FullOsd.Content" in content
assert "implicitWidth: 520" in content
assert "CortetsuActionTile" in qsd
assert "CortetsuSlider" in qsd
assert "CortetsuPower" in qsd
assert "ESTADO DEL SISTEMA" not in content
assert "state.osd = false" in qsd
print("PASS: OSD exposes the complete large system-control surface")
