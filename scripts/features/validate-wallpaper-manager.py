#!/usr/bin/env python3
"""Static contract gate for the native Cortetsu Wallpaper Manager."""
from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]


def require(path: Path, *needles: str) -> None:
    text = path.read_text(encoding="utf-8")
    for needle in needles:
        assert needle in text, f"{path.relative_to(ROOT)} missing {needle!r}"


def main() -> None:
    content = ROOT / "cortetsu/modules/wallpaper/Content.qml"
    require(content, "Orbit.arc(", "Orbit.arcAngle", "Orbit.prefetch", "Orbit.resolveCurrentIndex", "orbitPhase",
            "asynchronous: true", "sourceSize.width", "cache: true", "presentationReady",
            "CortetsuWallpapers.applyRandom()", "required property int index", "pendingPreviewPath",
            "interval: CortetsuDesign.wallUtilityOrbitMotionMs", "Orbit.wheelIntent", "heroCrossfade", "gridMode",
            "Orbit.previewEligible")
    content_text = content.read_text(encoding="utf-8")
    assert not re.search(r"\bQuickshell\.exec\(", content_text)
    assert "Orbit.visible(filteredEntries, currentIndex" not in content_text, "fixed slots would only swap sources"
    assert "source: satellite.modelData.entry.path" in content_text
    assert "import qs.components.effects" not in content_text
    assert "previewCurrent" not in content_text
    open_start = content_text.index("function openManager(): void")
    open_end = content_text.index("function closeManager", open_start)
    open_body = content_text[open_start:open_end]
    for contract in ("presentationReady = false", "resync(CortetsuWallpapers.actualCurrent);", "Qt.callLater(updatePresentationReady)", "forceActiveFocus();"):
        assert contract in open_body, f"openManager missing {contract}"
    assert 'if (accepted && CortetsuConfig.smartScheme)\n                CortetsuWallpapers.previewColourLock = true;' in content_text
    # The legacy Colours singleton, not CortetsuColours.
    assert not re.search(r"(?<![A-Za-z])Colours\.", content_text)
    assert "Item {\n        id: panel" in content_text and 'color: "black"' not in content_text
    wrapper_text = (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml").read_text(encoding="utf-8")
    assert "readonly property bool presentationReady" in wrapper_text
    assert "visible: opacity > 0.001" in wrapper_text
    assert "active: root.shouldBeActive || root.opacity > 0.001" in wrapper_text
    assert "Qt.alpha(CortetsuDesign.colorScrim, 0.18)" in wrapper_text
    require(ROOT / "cortetsu/modules/WallpaperController.qml", "wallpaperManager", "RetainedSurfaceController {", 'shortcutName: "wallpapermanager"')
    require(ROOT / "cortetsu/modules/RetainedSurfaceController.qml", "CortetsuShortcut", "name: root.shortcutName")
    require(ROOT / "cortetsu/modules/BottomHub.qml", "openWallpaperFor")
    require(ROOT / "config/hypr-user.lua", "SUPER + SHIFT + W", "cortetsu:wallpapermanager")
    service = ROOT / "cortetsu/modules/CortetsuWallpapers.qml"
    require(service, "pragma Singleton", "cortetsu-wallpaper-select", "previewGeneration", "requestGeneration", "cortetsu/wallpaper/path.txt")
    assert "caelestia" not in service.read_text(encoding="utf-8").lower()
    print("validate-wallpaper-manager: OK (first-party service and native manager contracts)")


if __name__ == "__main__":
    main()
