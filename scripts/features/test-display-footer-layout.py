#!/usr/bin/env python3
"""Keep the display editor's dry-run card clear of the overlaid footer."""

from pathlib import Path


root = Path(__file__).resolve().parents[2]
editor = (root / "cortetsu/modules/display/Editor.qml").read_text(encoding="utf-8")
content = (root / "cortetsu/modules/display/Content.qml").read_text(encoding="utf-8")

assert 'text: qsTr("Dry-run plan")' in editor
assert 'text: qsTr("Apply safely")' in (root / "cortetsu/modules/display/PreviewControls.qml").read_text(encoding="utf-8")
assert "- 150" in editor, "dry-run card must reserve the footer overlay"
assert "footerHeight: 120" in content
assert "footerMargin: 30" in content
print("PASS: display dry-run card reserves footer space at 1920x1080")
