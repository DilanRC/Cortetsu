#!/usr/bin/env python3
"""Gate the shared BottomHub hover timing contract."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
controller = (ROOT / "cortetsu/modules/CortetsuHoverSurfaceController.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")

assert "property int openDelay: 120" in controller
assert "property int closeDelay: 240" in controller
assert controller.startswith("pragma ComponentBehavior: Bound")
assert "Item {" in controller and "visible: false" in controller
assert "signal openRequested" in controller
assert "signal closeRequested" in controller
assert "CortetsuHoverSurfaceController" in hub
assert "hoverSurfaceController.request(screen, mode, anchorCenter)" in hub
assert "hoverSurfaceController.enterTrigger()" in hub
assert "hoverSurfaceController.leaveTrigger()" in hub
assert "openAttachedControlNow" in hub
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
view = (ROOT / "cortetsu/modules/CortetsuBottomHubView.qml").read_text(encoding="utf-8")
assert "signal attachedControlEntered" in segment
assert "signal attachedControlExited" in segment
assert "onAttachedControlEntered" in view
print("PASS: BottomHub uses one reusable delayed hover host with close grace")
