#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
content = (ROOT / "cortetsu/modules/session/Content.qml").read_text(encoding="utf-8")
action_row = (ROOT / "cortetsu/components/CortetsuActionRow.qml").read_text(encoding="utf-8")

assert "CortetsuActionRow" in content
assert "property bool danger" in action_row
assert "property bool selected" in action_row
assert "activeFocusOnTab" in action_row
assert "required property int index" in action_row
assert "focus: root.index === 0" in action_row
assert "Keys.onReturnPressed" in action_row
assert "root.forceActiveFocus()" in action_row
assert "root.pendingAction === actionRow.modelData.id" in content
assert "trailingIcon: actionRow.selected ? \"warning\" : \"chevron_right\"" in content
assert "onEntered: actionRow.hovered = true" not in content
assert "onPressedChanged: actionRow.pressed" not in content

print("PASS: session actions share first-party hover, focus, confirmation and danger states")
