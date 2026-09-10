#!/usr/bin/env python3
"""Deterministic eval for state ownership and overlay-policy compatibility."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
state = (ROOT / "cortetsu/modules/CortetsuScreenState.qml").read_text(encoding="utf-8")
policy = (ROOT / "cortetsu/modules/OverlayPolicy.js").read_text(encoding="utf-8")
content_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
controllers = [path.read_text(encoding="utf-8") for path in (ROOT / "cortetsu/modules").glob("*Controller.qml")]

checks = {
    "typed boundary owns retained writes": all(marker in state for marker in (
        "function setFlag(flag: string, value: bool): bool",
        'if (flag === "overview" || flag === "calendar" || flag === "clipboard"',
        "return setRetained(flag, value);",
    )),
    "policy supports typed and compatibility state": all(marker in policy for marker in (
        "function setFlag(state, flag, value)",
        'typeof state.setFlag === "function"',
        "state[flag] = value;",
    )),
    "controller layer has no backing-object reach-through": all(".legacyState" not in text for text in controllers),
    "shared drawer uses the first-party monitor registry": "CortetsuShellState.forScreen(screen)" in content_window and "property ScreenState screenState: ShellState.forScreen(screen)" not in content_window,
    "wallpaper close preserves its retained owner": all(marker in policy for marker in (
        "function closeForWallpaper(state)",
        '"displayManager"',
        '"hardware"',
    )),
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu state boundary eval: {sum(checks.values())}/{len(checks)}")
