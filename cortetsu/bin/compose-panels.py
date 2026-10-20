#!/usr/bin/env python3
"""Validate the staged drawer Panels.qml against the retained-surface host.

Retained surfaces (overview, clipboard, hardware, display, wallpaper and
calendar) are hosted once per screen by RetainedSurfacesHost.qml. This step
used to inject hidden copies into Panels.qml; every copy loaded its content
and ran its side effects a second time (double calendar syncs, a hidden
wallpaper manager closing panels). The composed file must not contain them.
"""
from __future__ import annotations

import sys
from pathlib import Path

if len(sys.argv) != 2:
    raise SystemExit("usage: compose-panels.py <runtime-root>")

root = Path(sys.argv[1])
path = root / "modules/drawers/Panels.qml"
host = root / "modules/RetainedSurfacesHost.qml"
for required in (path, host):
    if not required.is_file():
        raise SystemExit(f"missing {required.name}: {required}")
text = path.read_text(encoding="utf-8")
host_text = host.read_text(encoding="utf-8")

# Hosted once, in RetainedSurfacesHost; never in the drawer window.
retained_wrappers = (
    "Overview.Wrapper",
    "Clipboard.Wrapper",
    "Hardware.Wrapper",
    "Display.Wrapper",
    "Wallpaper.Wrapper",
    "Calendar.Wrapper",
)
required_imports = ('import "../../theme"',)
for required_import in required_imports:
    if required_import not in text.splitlines():
        raise SystemExit(f"missing import: {required_import}")
for wrapper in retained_wrappers:
    if text.count(wrapper) != 0 or host_text.count(wrapper + " {") != 1:
        raise SystemExit(f"invalid composed marker count: {wrapper} must be hosted once by RetainedSurfacesHost")

text = text.replace("        sidebar: sidebar\n", "")
path.write_text(text, encoding="utf-8")
print("PASS: drawer panels composed; retained surfaces hosted once")
