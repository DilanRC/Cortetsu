from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
hover = (ROOT / "cortetsu/modules/CortetsuHoverSurfaceController.qml").read_text(encoding="utf-8")
assert "radiusValue: CortetsuDesign.radiusLarge" in segment
assert "buttonSize: 40" in segment
assert "onHoveredChanged" in segment
assert "id: systemControlsHover" in segment
assert "signal systemControlsEntered()" in segment
assert "signal systemControlsExited()" in segment
assert "root.systemControlsEntered();" in segment
assert "root.systemControlsExited();" in segment
assert "root.syncSystemControlHover()" not in segment
assert "width: implicitWidth" in segment
assert "height: implicitHeight" in segment
assert "required property bool statusPopoutsEnabled" in segment
assert "statusPopoutsEnabled: CortetsuConfig.bar.popouts.statusIcons" in hub
assert "function cancelPending(): void" in hover
assert "onStatusIconsChanged(): void" in hub
panel_window = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
assert "visible: panel.visible && panel.width > 0" in panel_window
button = (ROOT / "cortetsu/modules/HubButton.qml").read_text(encoding="utf-8")
interactions = (ROOT / "cortetsu/modules/drawers/Interactions.qml").read_text(encoding="utf-8")
assert "property real visualScale" in button and "scale: 1" in button
assert "if (!popouts.bottomAttached" in interactions
print("PASS: system cluster uses consistent hit targets, grouped surface, and hover ownership")
