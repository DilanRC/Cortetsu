#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/calendar/Content.qml").read_text(encoding="utf-8")

checks = {
    "calendar imports the first-party component boundary": 'import "../../components"' in content,
    "calendar has no local FocusButton fork": "component FocusButton" not in content,
    "calendar has no Qt Quick Controls button": "import QtQuick.Controls" not in content,
    "header refresh and close are shared buttons": content.count("CortetsuButton {") >= 8,
    "month navigation is shared": 'icon: "chevron_left"' in content and 'icon: "chevron_right"' in content,
    "pomodoro actions are shared": 'icon: "skip_next"' in content and 'icon: "restart_alt"' in content,
}
missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: Calendar controls eval missing " + ", ".join(missing))

print(f"Calendar controls eval: {len(checks)}/{len(checks)} (100%)")
