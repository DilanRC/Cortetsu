#!/usr/bin/env python3
"""Gate the dedicated first-party host for full retained surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
wallpaper = (ROOT / "cortetsu/modules/wallpaper/Wrapper.qml").read_text(encoding="utf-8")

assert 'name: "retained-surfaces"' in host
assert "Variants {" in host
assert "model: CortetsuScreens.screens" in host
assert "required property ShellScreen modelData" in host
assert "CortetsuShellState.forScreen(modelData)" in host
assert "screen: modelData" in host
assert "CortetsuShellState.forActive()" not in host
assert "WlrLayershell.layer: WlrLayer.Overlay" in host
assert "WlrLayershell.keyboardFocus: surfaceOpen ? WlrKeyboardFocus.Exclusive" in host
for wrapper in ("Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper", "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper"):
    assert wrapper in host, wrapper
# Hosted exactly once per screen. The drawer window used to keep hidden
# copies that loaded their content and ran their side effects a second time
# (duplicate calendar syncs, a hidden Wallpaper Manager closing panels).
for wrapper in ("Overview.Wrapper", "Clipboard.Wrapper", "Hardware.Wrapper", "Display.Wrapper", "Wallpaper.Wrapper", "Calendar.Wrapper"):
    assert host.count(wrapper + " {") == 1, wrapper
    assert wrapper not in panels, f"Panels.qml instantiates {wrapper} a second time"
# One click on the Bottom Hub bell through the scrim: only where no panel
# covers it, never over Overview or during a Keyboards capture, and it runs the
# bell's own action (tools/stab_contracts.py `bell` checks the pointer path).
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
assert 'import "ScrimHit.js" as ScrimHit' in host
assert "onPressed: mouse => mouse.accepted = window.reachesBell(mouse.x, mouse.y)" in host
assert "return !keyboards.dismissBlocked" in host
assert "notificationsButtonContains(x, y)" in host and "ScrimHit.backdropOnly(surfaces, x, y)" in host
assert "enabled: window.surfaceOpen && !(window.screenState?.cortetsuState?.overview ?? false)" in host
assert "onClicked: window.screenState?.cortetsuState?.bottomHub?.activateNotifications()" in host
assert "onNotificationsRequested: hubRoot.toggleSidebarFor(win.modelData, bottomHubView.notificationsButton.pressedAt)" in hub
assert "function activateNotifications(): void {\n                hubRoot.toggleSidebarFor(win.modelData);" in hub
assert 'property: "bottomHub"' in hub
assert "opacity: shouldBeActive ? 1 : 0" in wallpaper
assert "Content.qml owns the honest empty state" in wallpaper
print("PASS: retained surfaces have monitor-local independent overlay ownership, hosted once per screen")
