#!/usr/bin/env python3
"""Regression: drawer interactions must write a real OSD hover property."""
from pathlib import Path

root = Path(__file__).resolve().parents[2]
wrapper = (root / 'cortetsu/modules/osd/Wrapper.qml').read_text(encoding='utf-8')
interactions = (root / 'cortetsu/modules/drawers/Interactions.qml').read_text(encoding='utf-8')
assert 'property alias hovered: content.hovered' in wrapper, 'OSD wrapper does not expose the property written by Interactions'
assert 'root.panels.osd.hovered =' in interactions, 'drawer interaction no longer updates OSD hover state'
content = (root / 'cortetsu/modules/osd/Content.qml').read_text(encoding='utf-8')
assert 'id: indicatorsHover' in content
assert 'onHoveredChanged: root.hovered = hovered' in content
assert 'onEntered: root.hovered = true' not in content
assert 'onExited: root.hovered = false' not in content
print('PASS: OSD hover assignment crosses a declared wrapper alias')
