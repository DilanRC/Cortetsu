#!/usr/bin/env python3
"""Deterministic V2 interaction regressions without a running shell."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"
content = (MODULES / "wallpaper/Content.qml").read_text(encoding="utf-8")
wrapper = (MODULES / "wallpaper/Wrapper.qml").read_text(encoding="utf-8")
orbit = (MODULES / "wallpaper/OrbitModel.js").read_text(encoding="utf-8")
policy = (MODULES / "OverlayPolicy.js").read_text(encoding="utf-8")
wallpaper_controller = (MODULES / "WallpaperController.qml").read_text(encoding="utf-8")
service = (ROOT / "cortetsu/modules/CortetsuWallpapers.qml").read_text(encoding="utf-8")
renderer = (ROOT / "cortetsu/modules/background/Wallpaper.qml").read_text(encoding="utf-8")
canonical = (ROOT / "scripts/features/apply-canonical-sad-wiring.sh").read_text(encoding="utf-8")
hypr = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")
hub = (MODULES / "BottomHub.qml").read_text(encoding="utf-8")
shortcuts = (MODULES / "Shortcuts.qml").read_text(encoding="utf-8")


def body(name: str) -> str:
    start = content.index(f"function {name}")
    return content[start:content.find("\n    function ", start + 1)]


# Neutral open: actualCurrent determines selection, then focus, with no preview path.
open_body = body("openManager")
resync_body = body("resync")
assert "resync();" in open_body and "forceActiveFocus();" in open_body
assert "CortetsuWallpapers.preview" not in open_body
assert "CortetsuWallpapers.actualCurrent" in resync_body and "Orbit.resolveCurrentIndex" in resync_body
assert "Orbit.resolveCurrentIndex" in body("selectCategory")
assert "function resolveCurrentIndex" in orbit and "function basename" in orbit

# A→B→C→D has one timer and the final stable candidate is the sole preview call.
assert content.count("Timer {") == 1
assert "interval: 220" in content
timer_body = content[content.index("id: previewTimer"):content.index("NumberAnimation {", content.index("id: previewTimer"))]
assert "Orbit.previewEligible" in timer_body
assert "CortetsuWallpapers.preview(root.pendingPreviewPath)" in timer_body
assert "previewTimer.restart()" in body("queuePreview")
assert "cancelPreview();" in body("requestTarget")

# Close, category/model reset, apply and random erase delayed work; active preview stops.
cancel_body = body("cancelPreview")
assert "previewTimer.stop();" in cancel_body and "CortetsuWallpapers.stopPreview();" in cancel_body
assert "cancelPreview();" in body("selectCategory") and "CortetsuWallpapers.preview" not in body("selectCategory")
assert "cancelPreview();" in resync_body
assert "previewTimer.stop();" in body("apply") and "CortetsuWallpapers.previewColourLock = true;" in body("apply")
assert "cancelPreview();" in body("random") and "CortetsuWallpapers.setRandom();" in body("random")
assert "closeManager();" in wrapper and "CortetsuWallpapers.stopPreview();" in wrapper
assert "globalOtherOverlayOpen" in wrapper and "onGlobalOtherOverlayOpenChanged" in wrapper
assert "for (const candidate of CortetsuScreens.screens)" in wrapper
assert "OverlayPolicy.hasCompetingPanel" in wrapper and "closeCompetingPanels();" in wrapper

# One policy covers both orders, including notification/sidebar and all retained overlays.
for other in ("launcher", "session", "dashboard", "utilities", "sidebar", "overview", "clipboard", "hardware", "displayManager", "wallpaperManager"):
    assert other in policy, f"policy does not exclude {other}"
for controller_file in ("OverviewController.qml", "ClipboardController.qml", "HardwareController.qml", "DisplayController.qml"):
    controller = (MODULES / controller_file).read_text(encoding="utf-8")
assert "OverlayPolicy.closeOtherPanels" in controller and "for (const screen of CortetsuScreens.screens)" in controller
assert "OverlayPolicy.closeForWallpaper" in wallpaper_controller and "for (const screen of CortetsuScreens.screens)" in wallpaper_controller
assert "OverlayPolicy.closeOtherPanels(state);" in hub
assert "toggleSidebarFor" in hub and "state.sidebar = !wasOpen;" in hub
assert "const state = CortetsuShellState.forActive()?.cortetsuState;" in wallpaper_controller
assert "CortetsuShellState.forActive()?.modelData" not in wallpaper_controller
assert "closeOtherPanels();\n        state.setRetained(\"wallpaperManager\", true);" in wallpaper_controller

# V2 visual and native-service contracts.
for needle in ("Orbit.satellites", "Math.min(12", "Math.cos(angle)", "Math.sin(angle)", "depth", "scale:", "opacity:", "z:", "CortetsuMask { maskSource", "outgoingHeroPath", "heroCrossfade", "component OrbitButton: CortetsuSurface"):
    assert needle in content, needle
for needle in ("id: header", "Wallpaper Forge", "Wallpaper-aware desktop surface", "cortetsu-mark.svg", 'icon: "close"', "onClicked: root.cancel()"):
    assert needle in content, needle
assert "source: satellite.modelData.entry.path" in content
assert "root.selectSatellite(satellite.modelData.index)" in content
assert "import qs.components.effects" not in content
assert "import qs.components.controls" not in content
assert "Image {\n            anchors.fill: parent; anchors.margins" not in content
assert 'if (CortetsuConfig.smartScheme)\n                CortetsuWallpapers.previewColourLock = true;' in content
assert "Colours." not in content

# V2.1 presentation: bounded shared-cache prefetch, ready-gated entry, and floating surfaces.
assert "Orbit.prefetch(filteredEntries, currentIndex, visibleLimit + 6)" in content
assert "Math.min(18, count)" in orbit
assert "property bool presentationReady: false" in content
assert "function updatePresentationReady" in content
assert content.count("onStatusChanged: root.updatePresentationReady()") >= 2
assert "Math.min(prefetchRepeater.count, 7)" in content
assert content.count("cache: true") >= 4
assert "id: panel\n        z: 1" in content and "Item {\n        id: panel" in content
assert "CortetsuDesign.colorSurfaceHigh, 0.68" in content
assert 'root.currentPath === CortetsuWallpapers.actualCurrent ? qsTr("Current") : qsTr("Preview")' in content
assert "opacity: shouldBeActive ? 1 : 0" in wrapper
assert "Content.qml owns the honest empty state" in wrapper
assert "CortetsuDesign.colorScrim, 0.18" in wrapper
assert "CortetsuDesign.colorScrim, 0.44" not in wrapper
assert 'color: "black"' not in content
for legacy in ("Caelestia.Config", "import Caelestia\n", "import qs.components\n", "Colours.palette", "Tokens.", "StyledText", "MaterialIcon"):
    assert legacy not in content + wrapper, legacy

# V2.2 orbital motion: the settled model stays stable during rotation and
# satellites communicate depth through scale, opacity and z-order.
assert "Orbit.satellites(filteredEntries, windowIndex, windowIndex, visibleLimit)" in content
assert "orbitMotion.to = orbitPhase - steps * Orbit.angularStep" in content
assert "root.windowIndex = root.currentIndex;" in content
assert "root.orbitPhase = 0;" not in content[content.index("NumberAnimation {"):content.index("ParallelAnimation {")]
assert "scale: 1" not in content
assert "currentStateLabel" in content and "currentIsApplied" in content
assert "scale: (0.72 + depth * 0.38)" not in content
assert "anchors.bottomMargin: 70" in content
assert "readonly property real radiusX" in content
assert "readonly property real radiusY" in content
assert "Math.cos(angle) * radiusX" in content
assert "Math.sin(angle) * radiusY" in content
assert "height: 40" in content
assert "anchors.top: header.bottom" in content
assert "anchors.topMargin: CortetsuDesign.spacingCompact" in content
assert "anchors.bottomMargin: -4" in content
wire_line = next(line for line in canonical.splitlines() if line.startswith("WIRE_JSON="))
assert "wire_sad_shell.py" in wire_line
assert "--features" not in wire_line, "canonical wiring must include all retained features"
assert '"SUPER + SHIFT + W"' in hypr and '"SUPER + W"' in hypr
assert '"SUPER + SHIFT + E"' not in hypr
assert "customDock\", \"launcher" in shortcuts
for needle in ("previewGeneration += 1", "requestGeneration === root.previewGeneration", "root.showPreview", "previewPalette.running = false"):
    assert needle in service, needle
assert "caelestia" not in service.lower()
for legacy in ("Caelestia.Config", "qs.services", "qs.components", "Colours.", "Tokens.", "StyledRect", "StyledText", "MaterialIcon"):
    assert legacy not in renderer, legacy
assert "CortetsuWallpapers.current" in renderer and "CortetsuWallpapers.fallback" in renderer

print("test-wallpaper-manager: OK (neutral open, final-candidate debounce, cancellation, wheel reversal, canonical retained wiring, and two-way overlay exclusion)")
