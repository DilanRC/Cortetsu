#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")

checks = {
    "first-party component boundary": 'import "../../components"' in content,
    "local orbit button removed": "component OrbitButton" not in content,
    "close action remains shared": 'tooltipText: qsTr("Close Wallpaper Manager")' in content,
    "footer actions share button primitive": content.count("CortetsuButton {") >= 4,
    "apply remains primary": 'label: qsTr("Apply")' in content and "active: true" in content,
    "random action remains wired": 'icon: "shuffle"' in content and "root.random()" in content,
}
missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: Wallpaper controls eval missing " + ", ".join(missing))

print(f"Wallpaper controls eval: {len(checks)}/{len(checks)} (100%)")
