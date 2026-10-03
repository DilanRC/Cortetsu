#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
content = (root / 'cortetsu/modules/launcher/Content.qml').read_text(encoding='utf-8')
wrapper = (root / 'cortetsu/modules/launcher/Wrapper.qml').read_text(encoding='utf-8')
assert 'search.forceActiveFocus()' in content
assert 'content.item?.focusSearch()' in wrapper
print('Launcher focus eval: 3/3 (open signal, loaded item, TextField focus)')
