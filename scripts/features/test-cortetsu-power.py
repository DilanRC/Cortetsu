#!/usr/bin/env python3
"""Gate contract for the shared first-party power capability."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
service = ROOT / "cortetsu/services/CortetsuPower.qml"
source = service.read_text(encoding="utf-8")
consumers = [
    ROOT / "cortetsu/modules/BottomHub.qml",
    ROOT / "cortetsu/modules/qsd/Content.qml",
    ROOT / "cortetsu/modules/dashboard/Dash.qml",
    ROOT / "cortetsu/modules/settings/SystemPage.qml",
    ROOT / "cortetsu/modules/lock/LockSurface.qml",
    ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml",
    ROOT / "cortetsu/modules/bar/components/StatusIcons.qml",
    ROOT / "cortetsu/modules/BatteryMonitor.qml",
]

assert service.is_file()
for marker in (
    "pragma Singleton",
    "property var device",
    "property bool devicePresent",
    "property bool ready",
    "property bool laptopBattery",
    "Number.isFinite(raw)",
    "Math.max(0, Math.min(1, raw))",
    "property bool available",
    "property bool hasBattery",
    "property int percent",
    "property bool charging",
    "property bool critical",
):
    assert marker in source, marker

for path in consumers:
    text = path.read_text(encoding="utf-8")
    assert "CortetsuPower" in text, path
    assert "UPower.displayDevice.percentage" not in text, path
    assert "UPowerDeviceState" not in text, path

service_loader = (ROOT / "cortetsu/modules/ServiceLoader.qml").read_text(encoding="utf-8")
assert "CortetsuPower;" in service_loader
assert "import Quickshell.Services.UPower" in (ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml").read_text(encoding="utf-8")
print("PASS: first-party surfaces share the CortetsuPower capability contract")
