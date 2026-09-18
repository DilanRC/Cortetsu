from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
utilities_wrapper = (ROOT / "cortetsu/modules/utilities/Wrapper.qml").read_text(encoding="utf-8")
osd = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")

for source in (utilities_wrapper, osd):
    for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours"):
        assert legacy not in source, legacy

assert "readonly property bool shouldBeActive: false" in utilities_wrapper
assert "Acciones rápidas" not in osd
assert "CortetsuActionTile" not in osd
assert "visible: true" in osd
assert "CortetsuProgressBar" in osd
assert "value: indicator.modelData.value" in osd
assert "Math.max(0, Math.min(1, root.value))" in progress
assert "CortetsuAudio.incrementVolume" in osd
assert "setBrightness" in osd
assert "id: indicatorSummary" in osd
assert "Row {\n                            CortetsuText" not in osd

print("PASS: Wave 4 Quick Settings and OSD stay first-party and state-legible")
