#!/usr/bin/env python3
"""Deterministic V2 interaction regressions without a running shell."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"
content = (MODULES / "wallpaper/Content.qml").read_text(encoding="utf-8")
wrapper = (MODULES / "wallpaper/Wrapper.qml").read_text(encoding="utf-8")
orbit = (MODULES / "wallpaper/OrbitModel.js").read_text(encoding="utf-8")
tile = (MODULES / "wallpaper/WallpaperTile.qml").read_text(encoding="utf-8")
stage = (MODULES / "wallpaper/WallpaperStage.qml").read_text(encoding="utf-8")
frame = (MODULES / "wallpaper/OctagonFrame.qml").read_text(encoding="utf-8")
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
refilter_body = body("refilter")
assert "resync(CortetsuWallpapers.actualCurrent);" in open_body and "keyTarget.forceActiveFocus();" in open_body
assert "CortetsuWallpapers.preview" not in open_body
# One place decides the selection: the preferred path, then the applied
# wallpaper, then the first entry.
assert refilter_body.index("Orbit.resolveCurrentIndex(filteredEntries, preferredPath)") < refilter_body.index("Orbit.resolveCurrentIndex(filteredEntries, CortetsuWallpapers.actualCurrent)")
assert "refilter(preferredPath);" in resync_body and "refilter(keep);" in body("selectCategory")
# A rescan or a failed apply keeps the candidate; a new applied wallpaper is followed.
assert "function onListChanged(): void { root.resync(root.currentPath); }" in content
assert "function onWallpaperApplyFailed(path: string, generation: int): void { root.resync(root.currentPath); }" in content
assert "function onActualCurrentChanged(): void { root.resync(CortetsuWallpapers.actualCurrent); }" in content
assert "function resolveCurrentIndex" in orbit and "function basename" in orbit

# A→B→C→D has one preview timer and a short post-apply Cosmic timer. The
# acknowledgement timeout is owned by the shared wallpaper service.
assert content.count("    Timer {") == 2
assert "interval: CortetsuDesign.wallUtilityOrbitMotionMs" in content
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
apply_body = body("apply")
assert "previewTimer.stop();" in apply_body and "CortetsuWallpapers.previewColourLock = true;" in apply_body
assert apply_body.index("CortetsuWallpapers.stopPreview();") < apply_body.index("CortetsuWallpapers.previewColourLock = true;")
assert "cancelPreview();" in body("random") and "CortetsuWallpapers.applyRandom();" in body("random")
cancel_body = content[content.index("function cancel(): void"):content.find("\n    function ", content.index("function cancel(): void") + 1)]
assert "cosmicPulseTimer.stop();" in cancel_body and "previewColourLock = false;" in cancel_body
assert "function closeManager(): void { cancel(); }" in content
assert "closeManager();" in wrapper and "CortetsuWallpapers.stopPreview();" in wrapper
assert "readonly property bool applying: CortetsuWallpapers.applying" in content
assert "onWallpaperApplySucceeded" in content and "onWallpaperApplyFailed" in content
assert "id: applyTimeout" not in content
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
assert "function open(screen): void" in wallpaper_controller
assert "function openActive(): void" in wallpaper_controller
assert "CortetsuShellState.forScreen(target)?.cortetsuState" in wallpaper_controller
assert "open(undefined);" in wallpaper_controller
assert "CortetsuShellState.forActive()?.modelData" not in wallpaper_controller
assert "closeOtherPanels();\n        state.setRetained(\"wallpaperManager\", true);" in wallpaper_controller
assert "function open(): void { root.openActive(); }" in wallpaper_controller
assert "WallpaperController.open(screen);" in hub
assert "candidate === screen" not in hub

# V2 visual and native-service contracts.
for needle in ("Orbit.arc(", "Orbit.clamp(Math.floor(panel.width / 236), 2, 7)", "Math.cos(angle)", "Math.sin(angle)", "depth", "scale:", "opacity:", "z:", "outgoingHeroPath", "heroCrossfade", "CortetsuButton {", "active: true"):
    assert needle in content, needle
for needle in ("id: header", "Wallpaper Orbital", "CortetsuSearchBar {", "CortetsuEvolvingMark", "markPhase", 'icon: "close"', "onClicked: root.cancel()"):
    assert needle in content, needle
assert "source: satellite.modelData.entry.path" in content
assert "root.select(satellite.modelData.index)" in content
assert "import qs.components.effects" not in content
assert "import qs.components.controls" not in content
assert "Image {\n            anchors.fill: parent; anchors.margins" not in content
assert 'if (accepted && CortetsuConfig.smartScheme)\n                CortetsuWallpapers.previewColourLock = true;' in content
content_without_first_party_colours = content.replace("CortetsuColours.", "")
assert "Colours." not in content_without_first_party_colours

# V2.1 presentation: bounded shared-cache prefetch, ready-gated entry, and floating surfaces.
assert "Orbit.prefetch(filteredEntries, currentIndex, visibleLimit + 6)" in content
assert "Math.min(18, count)" in orbit
assert "property bool presentationReady: false" in content
assert "function updatePresentationReady" in content
assert content.count("onStatusChanged: root.updatePresentationReady()") >= 2
assert "Math.min(prefetchRepeater.count, 7)" in content
assert "cache: true" in content and stage.count("cache: true") == 2 and "cache: true" in tile
assert stage.count("CortetsuMask { maskSource: heroMask }") == 2 and "CortetsuMask { maskSource: mask }" in tile
# The prefetch and the tiles must decode at one size to share the pixmap cache.
assert content.count("sourceSize.width: 256") == 1 and "sourceSize.width: 256" in tile
assert "id: panel\n        z: 2" in content and "Item {\n        id: panel" in content
assert "Qt.alpha(CortetsuDesign.colorSurface, 0.84)" in content
assert '? qsTr("Actual")' in content and 'qsTr("Vista previa")' in content and 'qsTr("No se pudo aplicar")' in content and "stateLabel: root.currentStateLabel" in content
assert "opacity: shouldBeActive ? 1 : 0" in wrapper
assert "Content.qml owns the honest empty state" in wrapper
assert "CortetsuDesign.colorScrim, 0.18" in wrapper
assert "CortetsuDesign.colorScrim, 0.44" not in wrapper
assert 'color: "black"' not in content
for legacy in ("Caelestia.Config", "import Caelestia\n", "import qs.components\n", "Colours.palette", "Tokens.", "StyledText", "MaterialIcon"):
    assert legacy not in content_without_first_party_colours + wrapper, legacy

# V2.2 orbital motion: the settled model stays stable during rotation and
# satellites communicate depth through scale, opacity and z-order.
assert "Orbit.arc(filteredEntries, windowIndex, arcHalf + 1)" in content
assert "orbitMotion.to = steps;" in content
# The turn ends by re-anchoring the model and clearing the phase together,
# so a satellite never jumps between two frames.
assert "root.windowIndex = root.currentIndex;\n            root.orbitPhase = 0;" in content
assert "scale: 1" in content
assert "scale: satellite.visualScale" in content
assert "opacity: satellite.hovered ? 1 : Math.min(1, satellite.depth * 4) * (0.34 + satellite.depth * 0.66)" in content
assert "currentStateLabel" in content and "currentIsApplied" in content
assert "scale: (0.72 + depth * 0.38)" not in content
assert "anchors.bottomMargin: CortetsuDesign.wallUtilityOrbitBottomGap" in content
assert "readonly property real radiusX" in content
assert "readonly property real radiusY" in content
assert "Math.cos(angle) * arcRegion.radiusX" in content
assert "Math.sin(angle) * arcRegion.radiusY" in content
assert "height: 40" in content
assert "anchors.top: header.bottom" in content
# The stage shows the wallpaper at 16:9 and the chamfer is shared, not redrawn.
assert "width: Math.min(parent.width, parent.height * 16 / 9)" in content and "height: width * 9 / 16" in content
assert "ShapePath" not in content + stage + tile and stage.count("OctagonFrame {") == 2 and tile.count("OctagonFrame {") == 2
# A failure is shown on the wallpaper that failed, not on whichever is selected.
assert "readonly property bool currentFailed: applyFailed && currentPath === CortetsuWallpapers.applyStatusPath" in content
assert frame.count("ShapePath {") == 1
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
