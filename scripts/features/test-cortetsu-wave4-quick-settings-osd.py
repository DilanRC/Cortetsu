from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
utilities_wrapper = (ROOT / "cortetsu/modules/utilities/Wrapper.qml").read_text(encoding="utf-8")
osd = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")

for source in (utilities_wrapper, osd):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, legacy

assert "readonly property bool shouldBeActive: false" in utilities_wrapper
assert 'import "../qsd" as FullOsd' in osd
assert "FullOsd.Content" in osd
assert "implicitWidth: 520" in osd
qsd = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
assert "CortetsuActionTile" in qsd
assert 'title: qsTr("Controles")' in qsd
assert 'title: qsTr("Niveles")' in qsd
assert 'title: qsTr("Energía")' not in qsd  # energy is a card label, not a section
assert "CortetsuSlider" in qsd
assert "CortetsuPower" in qsd
assert "Math.max(0, Math.min(1, root.value))" in progress
assert "state.osd = false" in qsd

print("PASS: Wave 4 Quick Settings and OSD stay first-party and state-legible")
