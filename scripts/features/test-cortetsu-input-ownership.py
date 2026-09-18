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
        "mask: window.dashboardEnabled && window.screenState?.dashboard ? null : emptyRegion" in source
        if name == "dashboard"
        else f"mask: window.screenState?.{flag} ? null : emptyRegion" in source
        or f"mask: {flag} ? null : emptyRegion" in source
    )
    assert mask_contract, name
    assert "Region { id: emptyRegion }" in source, name

print("PASS: inactive first-party overlay hosts expose an empty input region")
