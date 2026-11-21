#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
wrapper = (root / 'cortetsu/modules/osd/Wrapper.qml').read_text(encoding='utf-8')
content = (root / 'cortetsu/modules/osd/Content.qml').read_text(encoding='utf-8')
assert 'property alias hovered: content.hovered' in wrapper
# The control center stays until dismissed; only the transient OSD times out.
assert 'hideTimer' not in wrapper and 'id: compactTimer' in wrapper
assert 'onHoveredChanged: root.hovered = hovered' in content
assert 'onEntered: root.hovered = true' not in content
assert 'onExited: root.hovered = false' not in content
print('OSD hover eval: 6/6 (shared indicator island, hover bridge, no timeout on the control center)')
