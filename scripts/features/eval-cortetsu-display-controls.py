#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
editor = (ROOT / "cortetsu/modules/display/Editor.qml").read_text(encoding="utf-8")
preview = (ROOT / "cortetsu/modules/display/PreviewControls.qml").read_text(encoding="utf-8")
output_controls = (ROOT / "cortetsu/modules/display/DisplayOutputControls.qml").read_text(encoding="utf-8")
presets = (ROOT / "cortetsu/modules/display/DisplayPresets.qml").read_text(encoding="utf-8")
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text(encoding="utf-8")

assert editor.count("CortetsuButton") == 3
assert preview.count("CortetsuButton") == 4
assert output_controls.count("delegate: CortetsuButton") == 1
assert output_controls.count("active: modelData.active") == 1
assert "disabled: !modelData.enabled" in output_controls
assert "modeLayer" not in output_controls
assert "CortetsuToggle" in output_controls
assert "vrrLayer" not in output_controls
assert presets.count("CortetsuButton") == 3
assert "MouseArea" not in presets
assert "ActionButton" not in preview
assert 'tooltipText: qsTr("Refresh displays")' in editor
assert 'tooltipText: qsTr("Reset candidate")' in editor
assert 'tooltipText: qsTr("Close Display Manager")' in editor
assert "activeFocusOnTab" in button
assert "CortetsuTooltip" in button
assert "Keys.onSpacePressed" in button
for label in ("Preview", "Keep", "Save", "Revert"):
    assert f'label: qsTr("{label}")' in preview
print("PASS: Display controls share CortetsuButton focus, tooltip and semantic states")
