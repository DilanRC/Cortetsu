#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
files = list((ROOT / "cortetsu/components").rglob("*.qml"))
owned = [p for p in files if "Cortetsu" in p.name]
assert len(owned) >= 10, "native design system has too few owned primitives"
assert all("CortetsuDesign" in p.read_text(encoding="utf-8") for p in owned if p.name != "StyledWindow.qml")
assert (ROOT / "docs/CORTETSU_DESIGN_SYSTEM.md").is_file()
tooltip = (ROOT / "cortetsu/components/CortetsuTooltip.qml").read_text(encoding="utf-8")
assert "property Item target" in tooltip and "property bool hovered" in tooltip
assert all(
    "CortetsuTooltip" in (ROOT / "cortetsu/modules" / name).read_text(encoding="utf-8")
    for name in ("HubButton.qml", "CortetsuAppRail.qml", "CortetsuTraySegment.qml", "StatusPill.qml")
)
print(f"PASS: native design eval covers {len(owned)} first-party QML primitives and documentation")
