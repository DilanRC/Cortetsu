#!/usr/bin/env python3
"""Static contract for BottomHub attached-popout dwell and grace lifetime."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
modules = ROOT / "cortetsu/modules"
controller = (modules / "CortetsuHoverSurfaceController.qml").read_text(encoding="utf-8")
state = (modules / "CortetsuShellState.qml").read_text(encoding="utf-8")
wrapper = (modules / "bar/popouts/Wrapper.qml").read_text(encoding="utf-8")
status = (modules / "CortetsuStatusSegment.qml").read_text(encoding="utf-8")
bottom = (modules / "BottomHub.qml").read_text(encoding="utf-8")

# Trigger contract: audio/network/bluetooth/battery enter the same controller and
# explicitly leave it when the pointer exits the icon.
for mode in ("audio", "network", "bluetooth", "battery"):
    assert f'root.attachedControlEntered("{mode}"' in status, mode
assert "id: systemControlsHover" in status
assert "signal systemControlsEntered()" in status
assert "signal systemControlsExited()" in status
assert "root.systemControlsEntered();" in status
assert "root.systemControlsExited();" in status
assert "root.syncSystemControlHover()" not in status
assert "onAttachedControlEntered:" in bottom
assert "onSystemControlsEntered: hoverSurfaceController.enterTrigger()" in bottom
assert "onSystemControlsExited: hoverSurfaceController.leaveTrigger()" in bottom

# Dwell and grace are distinct phases; leaving before dwell completes cancels the
# pending open instead of flashing a stale popup later.
assert "property int openDelay: 120" in controller
assert "property int closeDelay: 240" in controller
assert "openTimer.restart();" in controller
assert "openTimer.stop();" in controller
assert "if (!pinned && !triggerHovered && !popupHovered)" in controller
assert "onPopupHoveredChanged:" in controller

# The attached popup itself publishes a non-blocking HoverHandler lifetime through
# shared shell state, so the grace timer is cancelled while the pointer is over it.
assert "property var attachedPopupHoverOwner: null" in state
assert "function enterAttachedPopup(owner)" in state
assert "function leaveAttachedPopup(owner)" in state
assert "readonly property bool popupHovered: CortetsuShellState.attachedPopupHoverOwner !== null" in controller
assert "readonly property bool pointerInside: popupHover.hovered && bottomAttached && hasCurrent && !closing" in wrapper
assert "HoverHandler {" in wrapper
assert "CortetsuShellState.enterAttachedPopup(root);" in wrapper
assert "CortetsuShellState.leaveAttachedPopup(root);" in wrapper
assert "Component.onDestruction: CortetsuShellState.leaveAttachedPopup(root)" in wrapper

print("PASS: status popouts use cancellable dwell, popup-hover ownership and close grace")
