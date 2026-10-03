#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"

for path in modules.rglob("*.qml"):
    text = path.read_text(encoding="utf-8")
    assert "sh -c" not in text, f"arbitrary shell in QML: {path.relative_to(repo)}"

for relative in (
    "hardware/EnergyPage.qml",
    "hardware/PowerPage.qml",
    "hardware/PowerAutomationPage.qml",
):
    text = (modules / relative).read_text(encoding="utf-8")
    assert "running: root.visible" in text, f"hidden-page polling regression: {relative}"
    assert "onVisibleChanged: { if (visible) refresh(); }" in text, f"missing wake-on-visible: {relative}"

hub = (modules / "HubButton.qml").read_text(encoding="utf-8")
status = (modules / "StatusPill.qml").read_text(encoding="utf-8")
surface = (modules / "CortetsuSurface.qml").read_text(encoding="utf-8")
design = (modules / "CortetsuDesign.js").read_text(encoding="utf-8")
visualiser = (modules / "background/Visualiser.qml").read_text(encoding="utf-8")
launcher = (modules / "launcher/Wrapper.qml").read_text(encoding="utf-8")
bottom_hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")

# Shared controls remain in the tab order but must not claim focus while an
# overlay is being constructed. Otherwise the last loaded control becomes the
# keyboard owner and Escape appears to be the only way back to normal input.
components = repo / "cortetsu/components"
for relative in (
    "CortetsuButton.qml",
    "CortetsuToggle.qml",
    "CortetsuSlider.qml",
    "CortetsuChoiceCard.qml",
    "CortetsuListRow.qml",
):
    text = (components / relative).read_text(encoding="utf-8")
    assert "focus: false" in text, f"{relative} steals focus while loading"
    assert "activeFocusOnTab" in text, f"{relative} lost keyboard traversal"

hub_button = (modules / "HubButton.qml").read_text(encoding="utf-8")
assert "focus: false" in hub_button, "HubButton steals focus while loading"

interactions = (modules / "drawers/Interactions.qml").read_text(encoding="utf-8")
assert "if (false &&" not in interactions, "dead interaction branch remains"

sidebar = (modules / "sidebar/Content.qml").read_text(encoding="utf-8")
assert "onClicked: {}" not in sidebar, "interactive-looking no-op remains"
assert "disabled: true" in sidebar, "read-only notification history lacks a disabled row contract"

assert 'import "CortetsuDesign.js" as CortetsuDesign' in hub
assert 'import "CortetsuDesign.js" as CortetsuDesign' in status
assert 'import "CortetsuDesign.js" as CortetsuDesign' in surface
assert "CortetsuSurface" in hub
assert "CortetsuSurface" in status
assert "Colours." not in hub
assert "Colours." not in status
assert "CortetsuDesign.colorTetsu" in surface
assert "CortetsuDesign.colorIndigo" in surface
assert "CortetsuDesign.colorVermillion" in surface
assert "CortetsuDesign.hoverScale" in hub
assert hub.count("CortetsuDesign.motionFastMs") >= 2
assert "CortetsuDesign.motionStandardMs" in status
assert "hoverScale = 1.025" in design
assert "motionFastMs = 120" in design
assert "motionPanelMs = 240" in design
assert "mouse.containsMouse ? 1.06 : 1" not in hub
assert "duration: 110" not in hub
assert "root.screen?.height ?? 0" in visualiser
assert "screen?.height ?? 0" in launcher
assert "modelData?.width ?? 0" in bottom_hub

calendar = (repo / "cortetsu/bin/cortetsu-calendar").read_text(encoding="utf-8")
pomodoro = (repo / "cortetsu/bin/cortetsu-pomodoro").read_text(encoding="utf-8")
assert '/ "cortetsu"' in calendar
assert 'state_home / "cortetsu/pomodoro.json"' in pomodoro

print("PASS: Cortetsu quality gate: cold hidden pages, native visual primitives, canonical state, no QML shell pipelines")
