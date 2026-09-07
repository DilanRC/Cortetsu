#!/usr/bin/env python3
"""Eval launcher type ownership and first-party imports."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")

checks = {
    "launcher imports first-party components": 'import "../../components"' in source,
    "launcher uses popup surface": "CortetsuPopupSurface" in source,
    "launcher uses search bar": "CortetsuSearchBar" in source,
    "launcher keeps keyboard activation": "Keys.onPressed" in source,
}
missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: launcher eval missing " + ", ".join(missing))
print(f"Launcher eval: {len(checks)}/{len(checks)} (100%)")
