from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
assert "radiusValue: CortetsuDesign.radiusLarge" in segment
assert "buttonSize: 40" in segment
assert "onHoveredChanged" in segment
panel_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
assert "visible: panel.visible && panel.width > 0" in panel_window
print("PASS: system cluster uses consistent hit targets, grouped surface, and hover ownership")
