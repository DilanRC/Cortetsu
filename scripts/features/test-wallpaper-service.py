from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
service = (repo / "cortetsu/modules/CortetsuWallpapers.qml").read_text()
wallpaper_list = (repo / "cortetsu/modules/launcher/WallpaperList.qml").read_text()
wallpaper_item = (repo / "cortetsu/modules/launcher/WallpaperItem.qml").read_text()
renderer = (repo / "cortetsu/modules/background/Wallpaper.qml").read_text()
background = (repo / "cortetsu/modules/background/Background.qml").read_text()
legacy_service = repo / "cortetsu/base/services/Wallpapers.qml"
launcher_content = (repo / "cortetsu/modules/launcher/Content.qml").read_text()
launcher_content_list = (repo / "cortetsu/modules/launcher/ContentList.qml").read_text()

assert not legacy_service.exists()
assert not re.search(r"(?<!Cortetsu)Wallpapers\.", launcher_content)
assert not re.search(r"(?<!Cortetsu)Wallpapers\.", launcher_content_list)

# The owned reactive palette is allowed; only the inherited bare Colours.
# namespace is retired.
service_for_audit = service.replace("CortetsuColours.", "")
for legacy in ("Caelestia", "qs.services", "Searcher", "FileSystemModel", "Colours.", "Paths."):
    assert legacy not in service_for_audit, legacy
for contract in ("cortetsu/wallpaper/path.txt", 'target: "cortetsu-wallpaper"', "function query", "function preview", "previewGeneration", "cortetsu-wallpaper-select", "cortetsu-wallpaper-colours"):
    assert contract in service, contract

print("PASS: Wallpaper service is first-party, XDG-owned and cancellation-aware")

for text in (wallpaper_list, wallpaper_item):
    for legacy in ("Caelestia", "qs.services", "qs.components", "Caelestia.Models", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon"):
        assert legacy not in text, legacy
assert "CortetsuWallpapers.query(query)" in wallpaper_list
assert "CortetsuWallpapers.preview(currentItem.modelData.path)" in wallpaper_list
assert "CortetsuWallpapers.setWallpaper(root.modelData.path)" in wallpaper_item
print("PASS: launcher wallpaper list and delegate are first-party")

for legacy in ("Caelestia", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon"):
    assert legacy not in renderer, legacy
for contract in ("CortetsuWallpapers.current", "asynchronous: true", "fillMode: Image.PreserveAspectCrop", "CortetsuWallpapers.fallback"):
    assert contract in renderer, contract

print("PASS: Wallpaper renderer is first-party and has a local fallback")

for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledWindow", "StyledRect", "StyledText", "MaterialIcon"):
    assert legacy not in background, legacy
for contract in ("PanelWindow", "CortetsuScreens.screens", "CortetsuConfig.wallpaperEnabled", "ShellState.ComponentRef", "sourceComponent: Wallpaper"):
    assert contract in background, contract

print("PASS: Background host is first-party and monitor-scoped")
