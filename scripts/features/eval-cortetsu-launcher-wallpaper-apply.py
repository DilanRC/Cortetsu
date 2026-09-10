#!/usr/bin/env python3
"""Product eval for honest wallpaper apply feedback across surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
manager = (ROOT / "cortetsu/modules/wallpaper/Content.qml").read_text(encoding="utf-8")
launcher = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
launcher_host = (ROOT / "cortetsu/modules/LauncherHost.qml").read_text(encoding="utf-8")
wallpaper_list = (ROOT / "cortetsu/modules/launcher/WallpaperList.qml").read_text(encoding="utf-8")
item = (ROOT / "cortetsu/modules/launcher/WallpaperItem.qml").read_text(encoding="utf-8")

checks = {
    "one shared transaction": "readonly property bool applying: pendingApplyPath.length > 0" in service,
    "shared status is explicit": 'readonly property string applyStatus: applying' in service and 'readonly property string applyStatusPath: applying ? pendingApplyPath : lastApplyPath' in service,
    "success preserves confirmed path": "applySucceeded = true;" in service and "lastApplyPath = next;" in service,
    "failure preserves target path": "applySucceeded = false;" in service and "lastApplyPath = path;" in service,
    "explicit success signal": "wallpaperApplySucceeded(string path, int generation)" in service,
    "explicit failure signal": "wallpaperApplyFailed(string path, int generation)" in service,
    "state-file acknowledgement": "wallpaperApplySucceeded(next, generation)" in service,
    "timeout is bounded": "motionDeliberateMs * 8" in service,
    "manager uses shared apply": "CortetsuWallpapers.apply(currentPath)" in manager,
    "manager consumes shared status": "readonly property string applyStatus: CortetsuWallpapers.applyStatus" in manager and 'applyStatus === "failed"' in manager,
    "launcher uses shared apply": "CortetsuWallpapers.apply(target)" in launcher,
    "launcher closes after success": "onWallpaperApplySucceeded" in launcher and "root.screenState.launcher = false" in launcher,
    "duplicate apply is disabled": "disabled: CortetsuWallpapers.applying" in item,
    "delegate keeps apply ownership in Content": "applyOwner: root.content" in wallpaper_list,
    "dedicated host has no legacy panel bundle": "panels: null" in launcher_host,
    "wallpaper list accepts dedicated host": "property var panels: null" in wallpaper_list,
    "bar geometry is null-safe": "panels?.bar?.implicitWidth ?? 0" in wallpaper_list,
    "popout geometry is null-safe": "const popouts = panels?.popouts" in wallpaper_list,
    "utility geometry is null-safe": "panels?.utilities?.implicitWidth ?? 0" in wallpaper_list,
    "wallpaper delegate imports Quickshell": "import Quickshell" in item,
    "delegate movement state is null-safe": "PathView.view?.moving ?? false" in item,
}

settings = (ROOT / "cortetsu/modules/settings/SystemPage.qml").read_text(encoding="utf-8")
checks.update({
    "settings consumes shared status": "CortetsuWallpapers.applyStatusPath" in settings and 'warningState: CortetsuWallpapers.applyStatus === "failed"' in settings,
})

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu Launcher wallpaper apply eval: {sum(checks.values())}/{len(checks)}")
