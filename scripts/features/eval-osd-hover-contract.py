#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
wrapper = (root / 'cortetsu/modules/osd/Wrapper.qml').read_text(encoding='utf-8')
assert 'property alias hovered: content.hovered' in wrapper
assert 'hideTimer.restart()' in wrapper and 'if (!content.hovered)' in wrapper
print('OSD hover eval: 3/3 (declared hover bridge, restart, timeout guard)')
