#!/usr/bin/env python3
"""Deterministic product-surface eval for Quick Settings and the OSD."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
utilities = (ROOT / "cortetsu/modules/utilities/Wrapper.qml").read_text(encoding="utf-8")
osd = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
qsd = (ROOT / "cortetsu/modules/osd/FullContent.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")

checks = {
    "legacy quick settings host is inert": "readonly property bool shouldBeActive: false" in utilities,
    "osd composes the complete large surface": "FullContent" in osd,
    "large surface keeps system controls": "CortetsuActionTile" in qsd and "CortetsuSlider" in qsd,
    "osd has a stable large width": "implicitWidth: 520" in osd,
    "large surface closes the OSD": "state.osd = false" in qsd,
    "large surface keeps power and network context": "CortetsuPower" in qsd and "networkName" in qsd,
    "osd uses the shared bounded level primitive": "CortetsuSlider" in qsd
    and "Math.max(0, Math.min(1, root.value))" in progress,
    "surfaces avoid legacy ownership": all(
        legacy not in utilities and legacy not in osd
        for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours")
    ),
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: Wave 4 eval missing " + ", ".join(missing))

print(f"Wave 4 Quick Settings/OSD eval: {len(checks)}/{len(checks)} (100%)")
