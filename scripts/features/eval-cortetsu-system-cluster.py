from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
hover = (ROOT / "cortetsu/modules/CortetsuHoverSurfaceController.qml").read_text(encoding="utf-8")
assert "radiusValue: CortetsuDesign.radiusLarge" in segment
assert "buttonSize: 40" in segment
assert "onHoveredChanged" in segment
assert "required property bool statusPopoutsEnabled" in segment
assert "statusPopoutsEnabled: CortetsuConfig.bar.popouts.statusIcons" in hub
assert "function cancelPending(): void" in hover
assert "onStatusIconsChanged(): void" in hub
panel_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
assert "visible: panel.visible && panel.width > 0" in panel_window
print("PASS: system cluster uses consistent hit targets, grouped surface, and hover ownership")
