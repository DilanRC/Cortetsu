#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text(encoding="utf-8")

for marker in (
    'property string tooltipText: ""',
    "CortetsuTooltip {",
    "target: root",
    "hovered: mouse.containsMouse",
    "focused: root.activeFocus",
    "text: root.tooltipText",
    "property real visualScale:",
    "scale: 1",
    "scale: root.visualScale",
):
    assert marker in button, marker

surfaces = {
    "qsd": ROOT / "cortetsu/modules/qsd/Content.qml",
    "settings": ROOT / "cortetsu/modules/settings/Content.qml",
    "dashboard": ROOT / "cortetsu/modules/dashboard/Dash.qml",
    "today": ROOT / "cortetsu/modules/dashboard/Today.qml",
    "calendar": ROOT / "cortetsu/modules/calendar/Content.qml",
    "wallpaper": ROOT / "cortetsu/modules/wallpaper/Content.qml",
    "audio popup": ROOT / "cortetsu/modules/bar/popouts/CortetsuAudioPopup.qml",
}
for name, path in surfaces.items():
    text = path.read_text(encoding="utf-8")
    assert "tooltipText:" in text, f"{name} has no button tooltip contract"

print("PASS: shared CortetsuButton owns hover/focus tooltips across first-party icon controls")
