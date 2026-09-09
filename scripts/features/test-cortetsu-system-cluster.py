from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
segment = (ROOT / "cortetsu/modules/CortetsuStatusSegment.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
hover = (ROOT / "cortetsu/modules/CortetsuHoverSurfaceController.qml").read_text(encoding="utf-8")
popup = (ROOT / "cortetsu/modules/bar/popouts/Wrapper.qml").read_text(encoding="utf-8")
button = (ROOT / "cortetsu/modules/HubButton.qml").read_text(encoding="utf-8")
interactions = (ROOT / "cortetsu/modules/drawers/Interactions.qml").read_text(encoding="utf-8")

assert "CortetsuSurface" in segment
assert "networkTooltip" in segment and "networkTooltip" in hub
assert '"sync"' in hub and "CortetsuNetwork.connecting" in hub
assert "signal %2%" in hub
assert "required property bool statusPopoutsEnabled" in segment
assert "statusPopoutsEnabled: CortetsuConfig.bar.popouts.statusIcons" in hub

# Rich system controls are one hover island. Individual icons may select a
# different mode, but only leaving the island starts the close grace period.
assert "id: systemControls" in segment
assert "width: implicitWidth" in segment
assert "height: implicitHeight" in segment
assert "id: systemControlsHover" in segment
assert "signal systemControlsEntered()" in segment
assert "signal systemControlsExited()" in segment
assert "root.systemControlsEntered();" in segment
assert "root.systemControlsExited();" in segment
assert "root.syncSystemControlHover()" not in segment
for mode in ("audio", "network", "bluetooth", "battery"):
    assert f'root.attachedControlEntered("{mode}"' in segment
for mode in ("network", "bluetooth", "battery"):
    assert f'if (root.statusPopoutsEnabled)\n                    root.attachedControlRequested("{mode}"' in segment
assert segment.count("tooltipOnHover: false") == 4
assert "property bool tooltipOnHover: true" in button
assert "property real visualScale" in button
assert "scale: 1" in button
assert "if (!popouts.bottomAttached" in interactions

# Trigger and popup ownership share one close-grace controller, and attached
# popups remain physically clear of the 60 px BottomHub trigger strip.
assert "property int openDelay: 120" in hover
assert "property int closeDelay: 240" in hover
assert "CortetsuShellState.attachedPopupHoverOwner !== null" in hover
assert "onPopupHoveredChanged" in hover
assert "property real bottomOffset: 60 + CortetsuDesign.spacingStandard" in popup
assert "popupHover.hovered && bottomAttached && hasCurrent && !closing" in popup
clip_wrapper = (ROOT / "cortetsu/modules/bar/popouts/ClipWrapper.qml").read_text(encoding="utf-8")
assert "width: implicitWidth" in clip_wrapper
assert "height: implicitHeight" in clip_wrapper

print("PASS: system cluster exposes live status and stable trigger-to-popup hover ownership")
