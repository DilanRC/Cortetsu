#!/usr/bin/env python3
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[2]
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
overview = (ROOT / "cortetsu/modules/OverviewController.qml").read_text(encoding="utf-8")
conditional_popout_closes = len(re.findall(
    r"if \(!wasOpen\)\n\s+(?:hubRoot\.)?closeAllPopouts\(\);", hub
))

checks = {
    "launcher closes popouts": conditional_popout_closes >= 1,
    "sidebar closes popouts": conditional_popout_closes >= 2,
    "quick settings closes popouts": conditional_popout_closes >= 3,
    "calendar closes popouts": "function openCalendarFor" in hub and "closeAllPopouts();" in hub,
    "wallpaper closes popouts": "function openWallpaperFor" in hub and "closeAllPopouts();" in hub,
    "overview closes popouts": "function closeAllPopouts(): void" in overview and "closeAllPopouts();" in overview,
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: panel/popout exclusivity missing " + ", ".join(missing))
print(f"Panel/popout exclusivity eval: {len(checks)}/{len(checks)} (100%)")
