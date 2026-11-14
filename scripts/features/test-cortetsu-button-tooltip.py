#!/usr/bin/env python3
import re
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

# Every icon-only CortetsuButton in first-party QML names itself in a tooltip.
# A fixed list of surfaces went stale when Dash.qml lost its buttons; the
# invariant is the label, not the file.
missing = []
for path in sorted((ROOT / "cortetsu").rglob("*.qml")):
    if "/base/" in path.as_posix():
        continue
    text = path.read_text(encoding="utf-8")
    for match in re.finditer(r"\bCortetsuButton\s*\{", text):
        depth, index = 1, match.end()
        while depth and index < len(text):
            depth += (text[index] == "{") - (text[index] == "}")
            index += 1
        body = text[match.end():index]
        if re.search(r'^\s*label:\s*""', body, re.M) and "tooltipText:" not in body:
            missing.append(f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, match.start()) + 1}")
assert not missing, "icon-only buttons without a tooltip: " + ", ".join(missing)
assert len(list((ROOT / "cortetsu").rglob("*.qml"))) > 100, "the scan found the QML tree"

print("PASS: shared CortetsuButton owns hover/focus tooltips across first-party icon controls")
