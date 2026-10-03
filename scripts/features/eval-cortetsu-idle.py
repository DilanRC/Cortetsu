#!/usr/bin/env python3
"""Deterministic eval for power-aware idle inhibition."""
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
idle = (ROOT / "cortetsu/modules/IdleMonitors.qml").read_text(encoding="utf-8")
power = (ROOT / "cortetsu/services/CortetsuPower.qml").read_text(encoding="utf-8")

checks = {
    "idle uses shared power state": "readonly property bool isCharging: !CortetsuPower.onBattery" in idle,
    "idle has no native-provider duplicate": "UPower" not in idle and "Quickshell.Services.UPower" not in idle,
    "power service owns on-battery readback": "readonly property bool onBattery: UPower.onBattery === true" in power,
    "all idle paths use one derived flag": idle.count("root.isCharging") >= 1 and "CortetsuConfig.idleInhibitWhenCharging" in idle,
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu idle power eval: {sum(checks.values())}/{len(checks)}")
