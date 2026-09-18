#!/usr/bin/env python3
"""Deterministic product-surface eval for Quick Settings and the OSD."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
utilities = (ROOT / "cortetsu/modules/utilities/Wrapper.qml").read_text(encoding="utf-8")
osd = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")
progress = (ROOT / "cortetsu/components/CortetsuProgressBar.qml").read_text(encoding="utf-8")

checks = {
    "legacy quick settings host is inert": "readonly property bool shouldBeActive: false" in utilities,
    "osd has no action card": "Acciones rápidas" not in osd and "CortetsuActionTile" not in osd,
    "osd keeps volume wheel control": "CortetsuAudio.incrementVolume" in osd and "CortetsuAudio.decrementVolume" in osd,
    "osd uses one shared surface": "CortetsuPopupSurface" in osd and "id: indicators" in osd,
    "osd keeps brightness wheel control": "root.monitor.setBrightness" in osd,
    "osd uses the shared bounded level primitive": "CortetsuProgressBar" in osd
    and "value: indicator.modelData.value" in osd
    and "Math.max(0, Math.min(1, root.value))" in progress,
    "osd distinguishes mute": "indicator.modelData.muted" in osd,
    "osd summary avoids invalid Row anchors": "id: indicatorSummary" in osd and "Row {\n                            CortetsuText" not in osd,
    "surfaces avoid legacy ownership": all(
        legacy not in utilities and legacy not in osd
        for legacy in ("Caelestia", "GlobalConfig", "qs.services", "qs.components", "Tokens", "Colours")
    ),
}

missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: Wave 4 eval missing " + ", ".join(missing))

print(f"Wave 4 Quick Settings/OSD eval: {len(checks)}/{len(checks)} (100%)")
