#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")

assert 'import "../../components"' in content
assert "component OrbitButton" not in content
assert "OrbitButton" not in content
assert content.count("CortetsuButton {") >= 4
for marker in (
    'label: qsTr("Cancel")',
    'icon: "shuffle"',
    'label: qsTr("Random")',
    'label: qsTr("Apply")',
    "active: true",
    "onClicked: root.apply()",
):
    assert marker in content, marker

print("PASS: Wallpaper Manager actions use the shared CortetsuButton interaction contract")
