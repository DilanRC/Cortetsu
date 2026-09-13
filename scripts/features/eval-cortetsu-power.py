#!/usr/bin/env python3
"""Deterministic eval for honest, consistent power state presentation."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
service = (ROOT / "cortetsu/services/CortetsuPower.qml").read_text(encoding="utf-8")
qsd = (ROOT / "cortetsu/modules/qsd/Content.qml").read_text(encoding="utf-8")
hub = (ROOT / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
dashboard = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
settings = (ROOT / "cortetsu/modules/settings/SystemPage.qml").read_text(encoding="utf-8")
lock = (ROOT / "cortetsu/modules/lock/LockSurface.qml").read_text(encoding="utf-8")
popup = (ROOT / "cortetsu/modules/bar/popouts/CortetsuBatteryPopup.qml").read_text(encoding="utf-8")
monitor = (ROOT / "cortetsu/modules/BatteryMonitor.qml").read_text(encoding="utf-8")

checks = {
    "clamps and rejects unready readings": all(marker in service for marker in (
        "root.ready && Number.isFinite(raw)",
        "Math.max(0, Math.min(1, raw))",
        ": -1;",
    )),
    "unavailable battery has no fake percentage": all(marker in service for marker in (
        "property bool hasBattery: root.laptopBattery && root.available",
        "property int percent: root.hasBattery ? Math.round(root.value * 100) : -1",
    )),
    "BottomHub uses shared critical state": all(marker in hub for marker in (
        "CortetsuPower.charging",
        "CortetsuPower.critical",
        "CortetsuPower.percent",
    )),
    "QSD uses shared capability": all(marker in qsd for marker in (
        "CortetsuPower.value",
        "CortetsuPower.available",
        "CortetsuPower.hasBattery",
    )),
    "surfaces use one value source": all("CortetsuPower" in text for text in (dashboard, settings, lock, popup)),
    "monitor starts and reacts through service": all(marker in monitor for marker in (
        "target: CortetsuPower",
        "onPercentChanged",
        "Component.onCompleted: root.inspect()",
    )),
    "progress bar preserves unavailable sentinel": "value: CortetsuPower.value" in popup,
    "power profile provider is imported": "import Quickshell.Services.UPower" in popup,
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"CortetsuPower eval: {sum(checks.values())}/{len(checks)}")
