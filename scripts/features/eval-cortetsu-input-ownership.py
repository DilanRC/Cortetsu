#!/usr/bin/env python3
"""Design eval for click-through ownership across first-party overlays."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
files = [
    ROOT / "cortetsu/modules/QsdHost.qml",
    ROOT / "cortetsu/modules/DashboardHost.qml",
    ROOT / "cortetsu/modules/SettingsHost.qml",
    ROOT / "cortetsu/modules/LauncherHost.qml",
    ROOT / "cortetsu/modules/SessionHost.qml",
    ROOT / "cortetsu/modules/RetainedSurfacesHost.qml",
]

passed = sum(
    "mask:" in path.read_text(encoding="utf-8")
    and "Region { id: emptyRegion }" in path.read_text(encoding="utf-8")
    for path in files
)
assert passed == len(files)
print(f"Cortetsu input ownership eval: {passed}/{len(files)} hosts have inactive click-through masks")
