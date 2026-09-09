#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
button = (ROOT / "cortetsu/components/CortetsuButton.qml").read_text(encoding="utf-8")
assert button.count("CortetsuTooltip {") == 1
assert button.count("root.tooltipText") == 1

paths = [
    ROOT / "cortetsu/modules/qsd/Content.qml",
    ROOT / "cortetsu/modules/settings/Content.qml",
    ROOT / "cortetsu/modules/dashboard/Dash.qml",
    ROOT / "cortetsu/modules/dashboard/Today.qml",
    ROOT / "cortetsu/modules/calendar/Content.qml",
    ROOT / "cortetsu/modules/wallpaper/Content.qml",
    ROOT / "cortetsu/modules/bar/popouts/CortetsuAudioPopup.qml",
]
for path in paths:
    text = path.read_text(encoding="utf-8")
    if 'label: ""' in text:
        assert "tooltipText:" in text, f"icon-only button without tooltip: {path.name}"

print(f"Cortetsu button tooltip eval: {len(paths) + 2}/{len(paths) + 2} (100%)")
