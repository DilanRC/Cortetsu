"""Regression for the DBus-backed CortetsuNetwork service (Task 11).

Guards against regressing back to nmcli polling and pins the exact contract
consumers (BottomHub.qml) rely on: active {strength, ssid} and
activeEthernet {connected}, both derived from Quickshell.Networking's
NetworkManager DBus binding, plus the well-formedness of the QML itself.
"""
import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
path = repo / "cortetsu/modules/CortetsuNetwork.qml"
text = path.read_text(encoding="utf-8")

assert text.startswith("pragma Singleton"), "must stay a Quickshell singleton"
assert "import Quickshell.Networking" in text

# Event-driven contract: reacts to Networking's bindable properties, no
# process spawning, no timers, no GlobalConfig/Caelestia coupling.
for banned in ("Quickshell.Io", "Process {", "StdioCollector", "Timer {", "nmcli", "GlobalConfig", "Caelestia"):
    assert banned not in text, f"regressed to disallowed pattern: {banned}"

# Public contract consumed by BottomHub.qml must be preserved exactly.
assert re.search(r"readonly property var active:", text)
assert re.search(r"readonly property var activeEthernet:", text)
assert "strength" in text and "ssid" in text and "connected: true" in text
assert "function strengthPercent" in text
assert "value *= 100" in text

# Balanced braces -> catches an obviously broken QML edit.
assert text.count("{") == text.count("}")

print("PASS: CortetsuNetwork is DBus-driven (Quickshell.Networking), zero Caelestia coupling")
