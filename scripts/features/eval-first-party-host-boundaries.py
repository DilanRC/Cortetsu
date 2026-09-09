#!/usr/bin/env python3
"""Evaluate that visible hosts are internally composed from Cortetsu modules."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
paths = [
    ROOT / "cortetsu/modules/QsdHost.qml",
    ROOT / "cortetsu/modules/SettingsHost.qml",
    ROOT / "cortetsu/modules/LauncherHost.qml",
    ROOT / "cortetsu/modules/DashboardHost.qml",
    ROOT / "cortetsu/modules/SessionHost.qml",
    ROOT / "cortetsu/modules/RetainedSurfacesHost.qml",
]
sources = [path.read_text(encoding="utf-8") for path in paths]
assert all("import qs." not in source for source in sources)
assert all("import Caelestia" not in source for source in sources)
assert all("CortetsuShellState.forScreen(modelData)" in source for source in sources)
assert all("WlrLayer.Overlay" in source for source in sources)
print(f"PASS: host boundary eval covers {len(paths)} monitor-local first-party surfaces")
