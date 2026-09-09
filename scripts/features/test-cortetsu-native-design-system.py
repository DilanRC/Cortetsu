#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
components = ROOT / "cortetsu/components"
design = (ROOT / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
required = (
    "CortetsuButton.qml",
    "CortetsuToggle.qml",
    "CortetsuSlider.qml",
    "CortetsuListRow.qml",
    "CortetsuChoiceCard.qml",
    "CortetsuActionTile.qml",
    "CortetsuActionRow.qml",
    "CortetsuTab.qml",
    "CortetsuSectionHeader.qml",
    "CortetsuTooltip.qml",
    "containers/CortetsuPopupHost.qml",
)
for name in required:
    assert (components / name).is_file(), f"missing first-party primitive: {name}"

for token in ("colorSurfaceGlass", "colorSurfaceGlassStrong", "radiusPill", "rowHeight", "motionPanelMs"):
    assert token in design, f"design token missing: {token}"

host = (components / "containers/CortetsuPopupHost.qml").read_text(encoding="utf-8")
for token in ("Keys.onEscapePressed", "dismissOnOutside", "WlrKeyboardFocus.OnDemand", "z: 100", "signal closed()"):
    assert token in host, f"popup host contract missing: {token}"

tooltip = (components / "CortetsuTooltip.qml").read_text(encoding="utf-8")
for token in ("property Item target", "property bool hovered", "property bool focused", "motionDeliberateMs", "CortetsuSurface", "CortetsuText"):
    assert token in tooltip, f"tooltip contract missing: {token}"

for name in ("HubButton.qml", "CortetsuAppRail.qml", "CortetsuTraySegment.qml", "StatusPill.qml"):
    consumer = (ROOT / "cortetsu/modules" / name).read_text(encoding="utf-8")
    assert "CortetsuTooltip" in consumer, f"{name} does not use the shared tooltip"
    assert "ToolTip {" not in consumer, f"{name} still owns a divergent tooltip"

for name in required[:-1]:
    text = (components / name).read_text(encoding="utf-8")
    assert "CortetsuDesign" in text, f"{name} does not consume Cortetsu tokens"
    assert (
        "signal" in text
        or name in ("CortetsuSectionHeader.qml", "CortetsuTooltip.qml")
    ), f"{name} has no interaction contract"

for path in (
    components / "CortetsuButton.qml",
    components / "CortetsuIcon.qml",
    components / "CortetsuSectionHeader.qml",
    ROOT / "cortetsu/modules/CortetsuIcon.qml",
    ROOT / "cortetsu/modules/osd/Content.qml",
):
    text = path.read_text(encoding="utf-8")
    assert "CortetsuTypography" in text, f"{path.name} must source font sizes from CortetsuTypography"
    assert "CortetsuDesign.iconMediumPx" not in text
    assert "CortetsuDesign.bodyPx" not in text
    assert "CortetsuDesign.labelLargePx" not in text
    assert "CortetsuDesign.labelSmallPx" not in text

for path in (components / "CortetsuIcon.qml", ROOT / "cortetsu/modules/CortetsuIcon.qml"):
    assert "color: CortetsuDesign.colorOnSurface" in path.read_text(encoding="utf-8")

print("PASS: Cortetsu design primitives expose shared tokens, states and popup focus contract")
