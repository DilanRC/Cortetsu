#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
wrapper = (root / 'cortetsu/modules/osd/Wrapper.qml').read_text(encoding='utf-8')
content = (root / 'cortetsu/modules/osd/Content.qml').read_text(encoding='utf-8')
assert 'property alias hovered: content.hovered' in wrapper
assert 'hideTimer.restart()' in wrapper and 'if (!content.hovered)' in wrapper
assert 'id: indicatorsHover' in content
assert 'onEntered: root.hovered = true' not in content
assert 'onExited: root.hovered = false' not in content
print('OSD hover eval: 6/6 (shared indicator island, hover bridge, restart, timeout guard)')
