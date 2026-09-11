#!/usr/bin/env python3
"""OSD must represent unsupported brightness instead of inventing zero."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
wrapper = (ROOT / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
content = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
assert "monitor?.supported ? monitor.brightness : -1" in wrapper
assert 'qsTr("Unavailable")' in content
assert "root.monitor?.supported" in content
print("PASS: OSD distinguishes unsupported brightness from a real 0% value")
