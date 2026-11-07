#!/usr/bin/env python3
"""Runs the CortetsuRegional.js logic under Node against mocked HTTP
fixtures (test-regional.node.js) and statically checks that the patched
upstream files delegate to CortetsuRegional instead of GlobalConfig.

No real network call is made anywhere in this test: the Open-Meteo,
Nominatim and ip-api response shapes are hand-built fixtures fed straight
to the pure parser functions.
"""
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MODULES = ROOT / "cortetsu/modules"

node = shutil.which("node")
assert node, "node is required to run test-regional.node.js"

result = subprocess.run(
    [node, str(ROOT / "cortetsu/tests/test-regional.node.js")],
    capture_output=True,
    text=True,
    check=False,
)
assert result.returncode == 0, f"test-regional.node.js failed:\n{result.stdout}\n{result.stderr}"
print(result.stdout.strip())

# Static contract: the singleton exists, is pure/pragma-library backed, and
# never duplicates CortetsuConfig as a second source of truth.
regional_qml = (MODULES / "CortetsuRegional.qml").read_text(encoding="utf-8")
regional_js = (MODULES / "CortetsuRegional.js").read_text(encoding="utf-8")
forecast = (MODULES / "lock/weather/Forecast.qml").read_text(encoding="utf-8")
weather = (ROOT / "cortetsu/services/Weather.qml").read_text(encoding="utf-8")
desktop_clock = (MODULES / "background/DesktopClock.qml").read_text(encoding="utf-8")
time_service = (ROOT / "cortetsu/services/Time.qml").read_text(encoding="utf-8")
bar_clock = (MODULES / "bar/components/Clock.qml").read_text(encoding="utf-8")
status_segment = (MODULES / "CortetsuStatusSegment.qml").read_text(encoding="utf-8")
dashboard = (MODULES / "dashboard/Dash.qml").read_text(encoding="utf-8")
lock_card = (MODULES / "lock/LockCard.qml").read_text(encoding="utf-8")
assert "pragma Singleton" in regional_qml
assert regional_js.startswith(".pragma library")
assert "readonly property bool useTwelveHourClock: CortetsuConfig.useTwelveHourClock" in regional_qml
assert "readonly property bool useSecondPrecision: CortetsuConfig.useSecondPrecision" in regional_qml
assert "SystemClock.Seconds : SystemClock.Minutes" in time_service
for consumer in (bar_clock, dashboard, lock_card):
    assert "Time.timeStr" in consumer, "all clock surfaces must share the selected time precision"
assert "text: Time.timeStr" in status_segment
assert 'Qt.formatDateTime(root.now, "HH:mm")' not in status_segment
assert "readonly property bool useFahrenheit: CortetsuConfig.useFahrenheit" in regional_qml
assert "readonly property string weatherLocation: CortetsuConfig.weatherLocation" in regional_qml
assert "property bool useTwelveHourClock:" not in regional_qml.split("readonly property bool useTwelveHourClock")[0], \
    "CortetsuRegional must not declare its own mutable copy of the preference"
assert "GlobalConfig" not in regional_qml and "GlobalConfig" not in regional_js
assert "import Caelestia" not in regional_qml and "import Caelestia" not in regional_js
assert "Caelestia.Config" not in regional_qml and "Caelestia.Config" not in regional_js

sources = forecast + weather + desktop_clock + regional_qml + regional_js
for needle in (
    "CortetsuRegional.clockPattern",
    "CortetsuRegional.formatTemperature(value)",
    "CortetsuRegional.parseLocationQuery(CortetsuRegional.weatherLocation)",
    "CortetsuRegional.buildIpLookupUrl()",
    "CortetsuRegional.parseIpLookupResponse(JSON.parse(text))",
    "CortetsuRegional.buildReverseGeocodeUrl(lat, lon, \"en\")",
    "CortetsuRegional.parseReverseGeocodeResponse(JSON.parse(text))",
    "CortetsuRegional.buildGeocodeUrl(parsed.value, \"en\")",
    "CortetsuRegional.parseGeocodeResponse(JSON.parse(text))",
    "CortetsuRegional.parseForecastResponse(JSON.parse(text))",
    "CortetsuRegional.buildForecastUrl(lat, lon)",
    "CortetsuRegional.hourPattern",
):
    assert needle in sources, f"missing regional delegation: {needle}"
for legacy in ("Caelestia", "GlobalConfig", "qs.components", "qs.services"):
    assert legacy not in forecast, legacy
assert "CortetsuSurface" in forecast and "CortetsuIcon" in forecast

print("test-regional: OK (mocked-HTTP JS logic + patch/singleton static contract)")
