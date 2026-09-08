#!/usr/bin/env python3
"""Gate that inactive first-party overlay layers do not steal application clicks."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
hosts = {
    "qsd": (ROOT / "cortetsu/modules/QsdHost.qml", "qsd"),
    "dashboard": (ROOT / "cortetsu/modules/DashboardHost.qml", "dashboard"),
    "settings": (ROOT / "cortetsu/modules/SettingsHost.qml", "settings"),
    "launcher": (ROOT / "cortetsu/modules/LauncherHost.qml", "launcher"),
    "session": (ROOT / "cortetsu/modules/SessionHost.qml", "open"),
    "retained": (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml", "surfaceOpen"),
}

for name, (path, flag) in hosts.items():
    source = path.read_text(encoding="utf-8")
    assert f"mask: window.screenState?.{flag} ? null : emptyRegion" in source or f"mask: {flag} ? null : emptyRegion" in source, name
    assert "Region { id: emptyRegion }" in source, name

print("PASS: inactive first-party overlay hosts expose an empty input region")
