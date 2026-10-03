#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
content = (root / 'cortetsu/modules/launcher/Content.qml').read_text(encoding='utf-8')
wrapper = (root / 'cortetsu/modules/launcher/Wrapper.qml').read_text(encoding='utf-8')
assert 'function focusSearch' in content, 'launcher has no explicit focus restoration function'
assert 'onLauncherChanged' in content and 'focusSearch()' in content, 'launcher does not refocus after opening'
assert 'content.item?.focusSearch()' in wrapper, 'launcher wrapper does not refocus loaded content on activation'
print('PASS: launcher has explicit focus restoration on open and activation')
