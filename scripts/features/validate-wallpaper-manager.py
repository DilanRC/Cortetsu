#!/usr/bin/env python3
"""Static contract gate for the native Cortetsu Wallpaper Manager."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def require(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        assert needle in text, f"{path.relative_to(ROOT)} missing {needle!r}"


def main() -> None:
    content = ROOT / "cortetsu/modules/wallpaper/Content.qml"
    require(content, "Orbit.satellites", "Orbit.prefetch", "Orbit.resolveCurrentIndex", "Orbit.satelliteAngle", "orbitPhase", "Math.min(12", "asynchronous: true", "sourceSize.width", "retainWhileLoading", "cache: true", "presentationReady", "CortetsuWallpapers.setRandom()", "CortetsuMask { maskSource", "layer.enabled: true", "visible: true", "required property int index", "pendingPreviewPath", "interval: 220", "Orbit.wheelIntent", "heroCrossfade")
    content_text = content.read_text(encoding="utf-8")
    assert "GridView" not in content_text and "Quickshell.exec" not in content_text
    assert "Orbit.visible(filteredEntries, currentIndex" not in content_text, "fixed slots would only swap sources"
    assert "source: satellite.modelData.entry.path" in content_text
    assert "import qs.components.effects" not in content_text
    assert "previewCurrent" not in content_text
    open_start = content_text.index("function openManager(): void")
    open_end = content_text.index("function closeManager", open_start)
    open_body = content_text[open_start:open_end]
    for contract in ("presentationReady = false", "resync();", "Qt.callLater(updatePresentationReady)", "forceActiveFocus();"):
        assert contract in open_body, f"openManager missing {contract}"
    assert 'if (CortetsuConfig.smartScheme)\n                CortetsuWallpapers.previewColourLock = true;' in content_text
    assert "Colours." not in content_text
    assert "Item {\n        id: panel" in content_text and 'color: "black"' not in content_text
    wrapper_text = (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml").read_text(encoding="utf-8")
    assert "readonly property bool presentationReady" in wrapper_text
    assert "visible: opacity > 0.001" in wrapper_text
    assert "active: root.shouldBeActive || root.opacity > 0.001" in wrapper_text
    assert "Qt.alpha(CortetsuDesign.colorScrim, 0.18)" in wrapper_text
    require(ROOT / "cortetsu/modules/WallpaperController.qml", "wallpaperManager", "CortetsuShortcut", 'name: "wallpapermanager"')
    require(ROOT / "cortetsu/modules/BottomHub.qml", "openWallpaperFor", "CortetsuWallpapers.actualCurrent")
    require(ROOT / "config/hypr-user.lua", "SUPER + SHIFT + W", "cortetsu:wallpapermanager")
    service = ROOT / "cortetsu/modules/CortetsuWallpapers.qml"
    require(service, "pragma Singleton", "cortetsu-wallpaper-select", "previewGeneration", "requestGeneration", "cortetsu/wallpaper/path.txt")
    assert "caelestia" not in service.read_text(encoding="utf-8").lower()
    print("validate-wallpaper-manager: OK (first-party service and native manager contracts)")


if __name__ == "__main__":
    main()
