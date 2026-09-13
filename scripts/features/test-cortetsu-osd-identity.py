from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "Acciones rápidas" in content
assert "CortetsuEvolvingMark" in content
assert 'phase: "Ascended"' in content
assert "animated: false" in content
assert "Grabar pantalla" in content
assert "Mantener activo" in content
assert "Activar modo juego" in content
assert "ESTADO DEL SISTEMA" not in content
assert "implicitWidth: 420" in content
print("PASS: OSD exposes the Cortetsu quick actions surface")
