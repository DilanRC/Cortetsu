from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/launcher/Content.qml").read_text(encoding="utf-8")
content_list = (ROOT / "cortetsu/modules/launcher/ContentList.qml").read_text(encoding="utf-8")
mode = (ROOT / "cortetsu/modules/CortetsuModeSegment.qml").read_text(encoding="utf-8")
assert "CortetsuSearchBar" in content and "onAccepted" in content
assert "CortetsuWallpapers.apply" in content
assert "ContentList" in content and "AppList" in content_list and "WallpaperList" in content_list
assert "showWallpapers" in content_list and "sourceComponent: AppList" in content_list
assert "evolvingMarkPhase" in mode
assert '"Human"' in mode and '"Awakening"' in mode and '"Monster"' in mode
assert '"Cosmic"' not in mode
print("PASS: launcher delegates app/wallpaper search and keeps mode identity in the BottomHub segment")
