#!/usr/bin/env python3
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
overview = (ROOT / "cortetsu/modules/OverviewController.qml").read_text(encoding="utf-8")


def body(name: str) -> str:
    return hub.split(f"function {name}(", 1)[1].split("\n    }\n", 1)[0]


checks = {
    "launcher closes popouts": "closeAllPopouts();" in body("toggleLauncherFor"),
    "sidebar closes popouts": "closeAllPopouts();" in body("toggleSidebarFor"),
    "quick settings closes popouts": "closeAllPopouts();" in body("toggleUtilitiesFor"),
    "session closes popouts": "hubRoot.closeAllPopouts();" in body("toggleSession"),
    "calendar closes popouts": "closeAllPopouts();" in body("openCalendarFor"),
    "wallpaper closes popouts": "closeAllPopouts();" in body("openWallpaperFor"),
    "overview closes popouts": "function closeAllPopouts(): void" in overview and "closeAllPopouts();" in overview,
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: panel/popout exclusivity missing " + ", ".join(missing))
print(f"Panel/popout exclusivity eval: {len(checks)}/{len(checks)} (100%)")
