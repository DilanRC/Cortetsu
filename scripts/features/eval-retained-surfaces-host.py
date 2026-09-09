#!/usr/bin/env python3
"""Small product eval for full-surface ownership and escape semantics."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
source = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
drawers = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
wrappers = [
    (ROOT / "cortetsu/modules/overview/Wrapper.qml", "overview"),
    (ROOT / "cortetsu/modules/clipboard/Wrapper.qml", "clipboard"),
    (ROOT / "cortetsu/modules/hardware/Wrapper.qml", "hardware"),
    (ROOT / "cortetsu/modules/display/Wrapper.qml", "displayManager"),
    (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml", "wallpaperManager"),
    (ROOT / "cortetsu/modules/calendar/Wrapper.qml", "calendar"),
]
launcher_list = (ROOT / "cortetsu/modules/launcher/ContentList.qml").read_text(encoding="utf-8")
null_safe_wrappers = {
    "launcher/Wrapper.qml": ("screenState?.launcher ?? false", "screenState?.dashboard"),
    "osd/Wrapper.qml": ("screenState?.osd", "root.screenState && !content.hovered"),
    "session/Wrapper.qml": ("screenState?.session === true",),
    "dashboard/Wrapper.qml": ("screenState?.dashboard === true",),
    "sidebar/Wrapper.qml": ("screenState?.sidebar ?? false",),
    "utilities/Wrapper.qml": ("screenState?.utilities ?? false", "screenState?.session ?? false"),
    "wallpaper/Wrapper.qml": ("screenState?.cortetsuState",),
}
checks = {
    "all retained content is first-party hosted": all(name in source for name in (
        "Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper",
        "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper",
    )),
    "host follows monitor-local state": all(marker in source for marker in (
        "model: CortetsuScreens.screens",
        "required property ShellScreen modelData",
        "CortetsuShellState.forScreen(modelData)",
        "screen: modelData",
    )) and "CortetsuShellState.forActive()" not in source,
    "escape closes the retained group": "closeRetainedOverlays()" in source,
    "full surfaces own overlay layer": "WlrLayer.Overlay" in source,
    "drawer resolves bar through explicit import boundary": 'import "../bar" as Bar' in drawers and "Bar.BarWrapper {" in drawers,
    "retained wrappers tolerate transient null state": all(f"screenState?.cortetsuState?.{flag}" in path.read_text(encoding="utf-8") for path, flag in wrappers),
    "launcher geometry tolerates transient null state": launcher_list.count("root.screenState?.launcher ?? false") == 2,
    "drawer wrappers tolerate transient null state": all(all(marker in (ROOT / "cortetsu/modules" / path).read_text(encoding="utf-8") for marker in markers) for path, markers in null_safe_wrappers.items()),
}
for label, passed in checks.items():
    if not passed:
        raise SystemExit(f"FAIL: {label}")
print(f"Retained surfaces host eval: {sum(checks.values())}/{len(checks)} (100%)")
