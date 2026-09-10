#!/usr/bin/env python3
"""Regression contract for transient tray-menu entries."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/bar/popouts/CortetsuTrayMenu.qml").read_text(encoding="utf-8")

assert "if (!entry)" in source, "tray activation must ignore stale entries"
assert "model: Array.from(opener.children ?? [])" in source
assert "filter(entry => entry !== null && entry !== undefined)" in source
assert "required property QsMenuEntry modelData" in source
assert "CortetsuPopupSurface" in source
assert "CortetsuStateLayer" in source
assert "Keys.onPressed" in source

print("PASS: tray menu filters transient null entries and keeps first-party input ownership")
