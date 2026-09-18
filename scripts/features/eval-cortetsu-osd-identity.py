from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")
assert "Acciones rápidas" not in content
assert "CortetsuActionTile" not in content
assert "id: indicators" in content
assert "CortetsuProgressBar" in content
assert "Behavior on width" in progress
print("PASS: OSD geometry stays restrained and animated with the existing motion contract")
