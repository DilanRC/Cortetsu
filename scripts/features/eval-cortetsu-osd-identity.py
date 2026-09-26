from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
qsd = (ROOT / "cortetsu/modules/osd/FullContent.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")
assert "FullContent" in content
assert "implicitWidth: 520" in content
assert "CortetsuActionTile" in qsd
assert "CortetsuSlider" in qsd
assert "CortetsuPower" in qsd
assert "Behavior on width" in progress
print("PASS: OSD exposes the complete large system-control surface")
