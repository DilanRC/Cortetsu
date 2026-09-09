#!/usr/bin/env python3
"""Product eval for canonical static identity usage across first-party surfaces."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SURFACES = {
    "OSD": ROOT / "cortetsu/modules/osd/Content.qml",
    "Dashboard": ROOT / "cortetsu/modules/dashboard/Dash.qml",
    "Settings": ROOT / "cortetsu/modules/settings/Content.qml",
}
QSD = ROOT / "cortetsu/modules/qsd/Content.qml"
LOCK = ROOT / "cortetsu/modules/lock/LockSurface.qml"

checks = {}
for name, path in SURFACES.items():
    content = path.read_text(encoding="utf-8")
    checks[f"{name} uses renderer"] = "CortetsuEvolvingMark" in content
    checks[f"{name} is stable Ascended"] = all(token in content for token in ('phase: "Ascended"', "animated: false"))
    checks[f"{name} keeps brand color private"] = "monochromeColor: CortetsuDesign.colorWashi" in content

qsd = QSD.read_text(encoding="utf-8")
checks["QSD uses renderer"] = "CortetsuEvolvingMark" in qsd
checks["QSD uses contextual phase"] = 'phase: root.markPhase' in qsd
checks["QSD keeps fixed 24px slot"] = "Layout.preferredWidth: 24" in qsd and "Layout.preferredHeight: 24" in qsd
checks["QSD keeps brand color private"] = "monochromeColor: CortetsuDesign.colorWashi" in qsd

lock = LOCK.read_text(encoding="utf-8")
checks["Lock uses renderer"] = "CortetsuEvolvingMark" in lock
checks["Lock uses contextual phase"] = 'phase: root.markPhase' in lock
checks["Lock keeps fixed 64px slot"] = "Layout.preferredWidth: 64" in lock and "Layout.preferredHeight: 64" in lock
checks["Lock keeps brand color private"] = "monochromeColor: CortetsuDesign.colorWashi" in lock

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu static/contextual brand surfaces eval: {sum(checks.values())}/{len(checks)}")
