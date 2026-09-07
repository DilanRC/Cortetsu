#!/usr/bin/env python3
"""Deterministic product-surface eval for Quick Settings and the OSD."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
utilities = (ROOT / "cortetsu/modules/utilities/Content.qml").read_text(encoding="utf-8")
osd = (ROOT / "cortetsu/modules/osd/Content.qml").read_text(encoding="utf-8")

checks = {
    "quick settings has a shared popup surface": "CortetsuPopupSurface" in utilities,
    "quick settings balances primary controls": "RowLayout" in utilities and "Layout.fillWidth" in utilities,
    "quick settings has an active recording status": "Screen recording active" in utilities,
    "quick settings has a ready status": "Cortetsu is ready" in utilities,
    "keep-awake remains actionable": "CortetsuIdleInhibitor.enabled = !CortetsuIdleInhibitor.enabled" in utilities,
    "recording remains actionable": "CortetsuRecorder.stop()" in utilities and '"cortetsu-record", "start"' in utilities,
    "notifications remain reachable": "root.screenState.sidebar = true" in utilities,
    "osd keeps volume wheel control": "CortetsuAudio.incrementVolume" in osd and "CortetsuAudio.decrementVolume" in osd,
    "osd uses one shared surface": "CortetsuPopupSurface" in osd and "id: indicators" in osd,
    "osd keeps brightness wheel control": "root.monitor.setBrightness" in osd,
    "osd renders a bounded level": "Math.max(0, Math.min(1, indicator.modelData.value))" in osd,
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
