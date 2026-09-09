#!/usr/bin/env python3
"""Deterministic wallpaper manager interaction regressions without a running shell."""
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
    end = content.find("\n    function ", start + 1)
    return content[start:] if end < 0 else content[start:end]


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
assert "interval: 260" in content
timer_body = content[content.index("id: previewTimer"):content.index("NumberAnimation {", content.index("id: previewTimer"))]
assert "Orbit.previewEligible" in timer_body
assert "CortetsuWallpapers.preview(root.pendingPreviewPath)" in timer_body
assert "previewTimer.restart()" in body("queuePreview")
assert "cancelPreview();" in body("requestTarget")

# Close, category/model reset, apply and random erase delayed work; active preview stops.
cancel_body = body("cancelPreview")
assert "previewTimer.stop();" in cancel_body and "CortetsuWallpapers.stopPreview();" in cancel_body
assert "cancelMotion();" in resync_body
assert "cancelPreview();" in body("selectCategory") and "cancelMotion();" in body("selectCategory")
assert "CortetsuWallpapers.preview" not in body("selectCategory")
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

# Orbital motion owns a stable snapshot. The committed selection stays untouched
# during the normal animation path, so the Repeater cannot churn underneath the
# NumberAnimation and turn movement into an apparent teleport.
for marker in (
    "property int motionTargetIndex: -1",
    "property var motionEntries: []",
    "property int motionOrbitCount: 0",
    "readonly property int displayIndex: animating && motionTargetIndex >= 0 ? motionTargetIndex : currentIndex",
    "readonly property var restingOrbitEntries: Orbit.satellites(filteredEntries, windowIndex, currentIndex, visibleLimit)",
    "readonly property var orbitEntries: animating ? motionEntries : restingOrbitEntries",
):
    assert marker in content, marker
animate_body = body("animateTo")
for marker in (
    "const snapshot = restingOrbitEntries.slice();",
    "motionEntries = snapshot;",
    "motionOrbitCount = Math.max(1, snapshot.length);",
    "motionTargetIndex = target;",
    "orbitPhase = 0;",
    "animating = true;",
    "orbitMotion.from = 0;",
    "orbitMotion.to = -steps * Orbit.angularStep(motionOrbitCount);",
):
    assert marker in animate_body, marker
assert animate_body.index("motionTargetIndex = target;") < animate_body.index("animating = true;")
assert "duration: 340" in content
assert "easing.type: Easing.OutCubic" in content
motion_stop = content[content.index("id: orbitMotion"):content.index("ParallelAnimation {", content.index("id: orbitMotion"))]
assert "const target = root.motionTargetIndex;" in motion_stop
assert "root.currentIndex = target;" in motion_stop and "root.windowIndex = target;" in motion_stop
assert "root.motionEntries = [];" in motion_stop and "root.motionOrbitCount = 0;" in motion_stop
assert "readonly property bool selected: satellite.modelData.index === root.displayIndex" in content

# Spatial hierarchy is a first-class part of the orbit rather than a flat ring.
for needle in (
    "Math.cos(angle)", "Math.sin(angle)", "depth",
    "scale: selected ? 1.18", "0.68 + depth * 0.40",
    "opacity: selected || hovered ? 1 : 0.36 + depth * 0.64",
    "z: selected ? 14", "Behavior on scale", "Behavior on opacity",
):
    assert needle in content, needle
assert "readonly property bool selected:" in content
assert "readonly property bool applied:" in content
assert "satellite.selected ? CortetsuDesign.colorTertiary" in content
assert "satellite.applied ? CortetsuDesign.colorSuccess" in content

# Hero preview is meaningful and visibly distinguishes selected/applied/loading state.
assert "readonly property bool currentApplied" in content
for label in ('qsTr("Loading")', 'qsTr("Applied")', 'qsTr("Selected")'):
    assert label in content
assert "root.animating ? 0.985 : 1" in content
assert "duration: 240" in content  # hero crossfade
assert 'root.previewActive ? qsTr("Previewing") : qsTr("Selected")' in content
assert "root.displayIndex + 1" in content

# Keyboard ownership includes both axes plus explicit apply/cancel.
assert "event.key === Qt.Key_Left || event.key === Qt.Key_Up" in content
assert "event.key === Qt.Key_Right || event.key === Qt.Key_Down" in content
assert "Qt.Key_Return" in content and "Qt.Key_Space" in content and "Qt.Key_Escape" in content

# Native visual/service contracts.
for needle in ("Orbit.satellites", "Math.min(12", "CortetsuMask { maskSource", "outgoingHeroPath", "heroCrossfade", "component OrbitButton: CortetsuSurface"):
    assert needle in content, needle
assert "source: satellite.modelData.entry.path" in content
assert "root.selectSatellite(satellite.modelData.index)" in content
assert "import qs.components.effects" not in content
assert "import qs.components.controls" not in content
assert 'if (CortetsuConfig.smartScheme)\n                CortetsuWallpapers.previewColourLock = true;' in content
assert "Colours." not in content

# Bounded shared-cache prefetch, ready-gated entry, and floating surfaces.
assert "Orbit.prefetch(filteredEntries, displayIndex, visibleLimit + 6)" in content
assert "Math.min(18, count)" in orbit
assert "property bool presentationReady: false" in content
assert "function updatePresentationReady" in content
assert content.count("onStatusChanged: root.updatePresentationReady()") >= 2
assert "Math.min(prefetchRepeater.count, 7)" in content
assert content.count("cache: true") >= 4
assert "id: panel\n        z: 1" in content and "Item {\n        id: panel" in content
assert "CortetsuDesign.colorSurfaceHigh, 0.68" in content
assert "opacity: shouldBeActive ? 1 : 0" in wrapper
assert "Content.qml owns the honest empty state" in wrapper
assert "CortetsuDesign.colorScrim, 0.18" in wrapper
assert "CortetsuDesign.colorScrim, 0.44" not in wrapper
assert 'color: "black"' not in content
for legacy in ("Caelestia.Config", "import Caelestia\n", "import qs.components\n", "Colours.palette", "Tokens.", "StyledText", "MaterialIcon"):
    assert legacy not in content + wrapper, legacy

# Orbital geometry still clears the footer and canonical wiring includes retained surfaces.
assert "anchors.bottomMargin: 70" in content
assert "readonly property real radiusX" in content
assert "readonly property real radiusY" in content
assert "Math.cos(angle) * radiusX" in content
assert "Math.sin(angle) * radiusY" in content
assert "anchors.topMargin: 0" in content
assert "anchors.topMargin: 56" in content
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

print("test-wallpaper-manager: OK (stable-snapshot orbital motion, selected/applied hierarchy, keyboard navigation, preview debounce, and overlay exclusion)")
