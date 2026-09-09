#!/usr/bin/env python3
"""Product eval for canonical static identity usage across first-party surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SURFACES = {
    "QSD": ROOT / "cortetsu/modules/qsd/Content.qml",
    "OSD": ROOT / "cortetsu/modules/osd/Content.qml",
    "Dashboard": ROOT / "cortetsu/modules/dashboard/Dash.qml",
    "Settings": ROOT / "cortetsu/modules/settings/Content.qml",
    "Lock": ROOT / "cortetsu/modules/lock/LockSurface.qml",
}

checks = {}
for name, path in SURFACES.items():
    content = path.read_text(encoding="utf-8")
    checks[f"{name} uses renderer"] = "CortetsuEvolvingMark" in content
    checks[f"{name} is stable Ascended"] = all(token in content for token in ('phase: "Ascended"', "animated: false"))
    checks[f"{name} keeps brand color private"] = "monochromeColor: CortetsuDesign.colorWashi" in content

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu static brand surfaces eval: {sum(checks.values())}/{len(checks)}")
