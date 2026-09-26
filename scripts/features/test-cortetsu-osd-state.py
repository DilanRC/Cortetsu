#!/usr/bin/env python3
"""OSD must represent unsupported brightness instead of inventing zero."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
wrapper = (ROOT / "cortetsu/modules/osd/Wrapper.qml").read_text(encoding="utf-8")
content = (ROOT / "cortetsu/modules/osd/FullContent.qml").read_text(encoding="utf-8")
assert "monitor?.supported ? monitor.brightness : -1" in wrapper
assert 'qsTr("No disponible")' in content
assert "brightnessMonitor" in content
print("PASS: OSD distinguishes unsupported brightness from a real 0% value")
