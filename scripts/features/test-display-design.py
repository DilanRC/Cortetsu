import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
display = repo / "cortetsu/modules/display"
legacy = ("Caelestia", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon")

for path in sorted(display.glob("*.qml")):
    text = path.read_text()
    for symbol in legacy:
        assert symbol not in text, f"{path.name}: {symbol}"
    assert not re.search(r"(?<!Cortetsu)StateLayer\b", text), path.name

assert "CortetsuStateLayer" in (display / "Editor.qml").read_text()
editor = (display / "Editor.qml").read_text(encoding="utf-8")
preview = (display / "PreviewControls.qml").read_text(encoding="utf-8")
output_controls = (display / "DisplayOutputControls.qml").read_text(encoding="utf-8")
presets = (display / "DisplayPresets.qml").read_text(encoding="utf-8")
assert 'import "../../components"' in editor
assert 'import "../../components"' in preview
assert "CortetsuButton" in editor and "CortetsuButton" in preview
assert 'tooltipText: qsTr("Previous display mode")' in editor
assert 'tooltipText: qsTr("Decrease %1").arg(modelData.label)' in editor
assert 'label: planner.running ? qsTr("Validating…") : qsTr("Dry run candidate")' in editor
assert 'import "../../components"' in output_controls
assert "delegate: CortetsuButton" in output_controls
assert "modeLayer" not in output_controls
assert "CortetsuToggle" in output_controls
assert "vrrLayer" not in output_controls
assert 'import "../../components"' in presets
assert "CortetsuButton" in presets
assert "MouseArea" not in presets
assert "ActionButton" not in preview
print("PASS: Display Manager uses Cortetsu visual primitives")
