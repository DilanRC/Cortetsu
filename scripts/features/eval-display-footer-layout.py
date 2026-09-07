#!/usr/bin/env python3
"""Evaluate the display footer geometry contract."""

from pathlib import Path


root = Path(__file__).resolve().parents[2]
editor = (root / "cortetsu/modules/display/Editor.qml").read_text(encoding="utf-8")
preview = (root / "cortetsu/modules/display/PreviewControls.qml").read_text(encoding="utf-8")

checks = {
    "footer reservation": "- 150" in editor,
    "dry-run card exists": 'text: qsTr("Dry-run plan")' in editor,
    "apply-safe controls exist": 'text: qsTr("Apply safely")' in preview,
    "preview controls remain bounded": 'height: root.footerHeight' in (root / "cortetsu/modules/display/Content.qml").read_text(encoding="utf-8"),
}
failed = [name for name, passed in checks.items() if not passed]
if failed:
    raise SystemExit("FAIL: " + ", ".join(failed))
print(f"Display footer layout eval: {len(checks)}/{len(checks)} (100%)")
