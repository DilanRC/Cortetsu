#!/usr/bin/env python3
"""Every asset a staged QML file names must be in the staged runtime.

The build copies assets/ folder by folder; a new folder (the paper grain
in assets/texture) was referenced for a whole release without being copied,
and the surfaces silently lost it. This reads the staged tree, not the
repository, so it catches exactly that.
"""
import re
import sys
from pathlib import Path

staging = Path(sys.argv[1])
shell_path = re.compile(r'shellPath\("(assets/[^"]+)"\)')
resolved = re.compile(r'Qt\.resolvedUrl\("((?:\.\./)+assets/[^"]+)"\)')
missing = []
checked = 0
for qml in staging.rglob("*.qml"):
    text = qml.read_text(encoding="utf-8", errors="replace")
    for rel in shell_path.findall(text):
        checked += 1
        if not (staging / rel).exists():
            missing.append(f"{qml.relative_to(staging)}: {rel}")
    for rel in resolved.findall(text):
        checked += 1
        if not (qml.parent / rel).resolve().exists():
            missing.append(f"{qml.relative_to(staging)}: {rel}")
assert checked > 0, "no asset references found: the pattern no longer matches"
assert not missing, "assets referenced but not staged:\n  " + "\n  ".join(missing)
print(f"PASS: {checked} asset references resolve inside the staged runtime")
