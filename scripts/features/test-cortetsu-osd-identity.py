from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "Acciones rápidas" not in content
assert "CortetsuActionTile" not in content
assert "id: indicators" in content
assert "value: indicator.modelData.value" in content
assert "ESTADO DEL SISTEMA" not in content
assert "implicitWidth: 360" in content
print("PASS: OSD exposes only transient level feedback")
