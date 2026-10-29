#!/usr/bin/env python3
"""Gate that inactive first-party overlay layers do not steal application clicks."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
hosts = {
    "dashboard": (ROOT / "cortetsu/modules/DashboardHost.qml", "dashboard"),
    "launcher": (ROOT / "cortetsu/modules/LauncherHost.qml", "launcher"),
    "session": (ROOT / "cortetsu/modules/SessionHost.qml", "open"),
    "retained": (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml", "surfaceOpen"),
}

for name, (path, flag) in hosts.items():
    source = path.read_text(encoding="utf-8")
    mask_contract = (
        "mask: window.open ? null : emptyRegion" in source
        and "readonly property bool open: window.dashboardEnabled && (screenState?.dashboard ?? false)" in source
        if name == "dashboard"
        else f"mask: window.screenState?.{flag} ? null : emptyRegion" in source
        or f"mask: {flag} ? null : emptyRegion" in source
    )
    assert mask_contract, name
    assert "Region { id: emptyRegion }" in source, name
    # A closed host must not stay mapped: an idle Overlay layer keeps a
    # fullscreen window from being the solitary client (no direct scanout).
    assert "visible: true" not in source, f"{name} host is always mapped"

drawers = (ROOT / "cortetsu/modules/drawers/ContentWindow.qml").read_text(encoding="utf-8")
assert "visible: fsTransitionProg < 1 || hasVisibleContent" in drawers, "drawers stays mapped over fullscreen"

print("PASS: inactive first-party overlay hosts expose an empty input region and are unmapped while closed")
