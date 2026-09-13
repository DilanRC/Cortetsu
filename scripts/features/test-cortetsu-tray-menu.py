#!/usr/bin/env python3
"""Regression contract for live tray-menu entries and popup sizing."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/bar/popouts/CortetsuTrayMenu.qml").read_text(encoding="utf-8")

assert "if (!entry)" in source, "tray activation must ignore stale entries"
assert "model: opener.children" in source
assert "childrenRect.height" in source
assert "required property QsMenuEntry modelData" in source
assert "CortetsuPopupSurface" in source
assert "CortetsuStateLayer" in source
assert "Keys.onPressed" in source
assert "menuMaxWidth: 220" in source
assert "TextMetrics" in source and "Text.ElideRight" in source
assert "property real naturalWidth" in source
assert "outlined: false" in source
assert "implicitSize: 16" in source
assert "modelData?.icon ?? \"\"" in source
assert "modelData?.text ?? \"\"" in source
assert "modelData?.hasChildren ?? false" in source

print("PASS: tray menu keeps the live ObjectModel and sizes from rendered content")
