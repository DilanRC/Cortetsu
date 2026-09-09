#!/usr/bin/env python3
"""Static contract gate for the shared Launcher/Wallpaper apply lifecycle."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
manager = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
launcher = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
wallpaper_list = (ROOT / "cortetsu/modules/launcher/WallpaperList.qml").read_text(encoding="utf-8")
wallpaper_item = (ROOT / "cortetsu/modules/launcher/WallpaperItem.qml").read_text(encoding="utf-8")


def function_body(source: str, name: str) -> str:
    start = source.index(f"function {name}")
    end = source.find("\n    function ", start + 1)
    return source[start:] if end < 0 else source[start:end]


apply_body = function_body(service, "apply")
read_body = function_body(service, "readActual")
fail_body = function_body(service, "failApply")
request_start = launcher.index("function requestWallpaper")
request_body = launcher[request_start:launcher.index("\n    implicitWidth", request_start)]

assert "function apply(path: string): bool" in service
assert "readonly property bool applying: pendingApplyPath.length > 0" in service
assert "property int applyGeneration: 0" in service
assert "signal wallpaperApplySucceeded(string path, int generation)" in service
assert "signal wallpaperApplyFailed(string path, int generation)" in service
assert "applyTimeout" in service and "cortetsu-wallpaper-select" in apply_body
assert "wallpaperApplySucceeded(next, generation)" in read_body
assert "wallpaperApplyFailed(path, generation)" in fail_body
assert "actualCurrent = next" in read_body

assert "function requestWallpaper(path: string): void" in launcher
assert "CortetsuWallpapers.applying" in request_body
assert "CortetsuWallpapers.apply(target)" in request_body
accepted_body = request_body[request_body.index("if (CortetsuWallpapers.apply(target))"):]
assert "root.screenState.launcher = false" not in accepted_body
assert "root.requestWallpaper(currentItem.modelData.path)" in launcher
assert "CortetsuWallpapers.setWallpaper" not in launcher
assert "onWallpaperApplySucceeded" in launcher
assert "root.screenState.launcher = false" in launcher[launcher.index("onWallpaperApplySucceeded"):]

assert "required property var applyOwner" in wallpaper_item
assert "disabled: CortetsuWallpapers.applying" in wallpaper_item
assert "root.applyOwner.requestWallpaper(root.modelData.path)" in wallpaper_item
assert "applyOwner: root.content" in wallpaper_list

assert "readonly property bool applying: CortetsuWallpapers.applying" in manager
assert "CortetsuWallpapers.apply(currentPath)" in manager
assert "CortetsuWallpapers.applyRandom()" in manager
assert "id: applyTimeout" not in manager
assert "onWallpaperApplySucceeded" in manager and "onWallpaperApplyFailed" in manager

print("test-cortetsu-launcher-wallpaper-apply: OK")
