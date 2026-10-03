#!/usr/bin/env python3
"""Evaluate the visible-surface import boundary, not only the host files."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"
paths = sorted(MODULES.rglob("*.qml"))
sources = [path.read_text(encoding="utf-8") for path in paths]

assert paths
assert all("import qs." not in source for source in sources)
assert all("import Caelestia" not in source for source in sources)
for relative, import_line in {
    "BottomHub.qml": 'import "../utils"',
    "CortetsuRecorder.qml": 'import "../utils"',
    "drawers/Panels.qml": 'import "../bar" as Bar',
    "launcher/Content.qml": 'import "services"',
    "sidebar/Content.qml": 'import "../notifications" as NotificationComponents',
}.items():
    source = (MODULES / relative).read_text(encoding="utf-8")
    assert import_line in source, f"{relative} lost its local boundary"

print(f"PASS: first-party surface import eval covers {len(paths)} active QML files")
