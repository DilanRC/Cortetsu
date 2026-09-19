from pathlib import Path

repo = Path(__file__).resolve().parents[2]
config = (repo / "cortetsu/modules/CortetsuConfig.qml").read_text(encoding="utf-8")
idle = (repo / "cortetsu/modules/IdleMonitors.qml").read_text(encoding="utf-8")
assert "idleTimeouts" in config
assert "idleInhibitWhenAudio" in config
assert "idleLockBeforeSleep" in config
assert "GlobalConfig" not in idle
assert "Caelestia" not in idle
assert "SessionManager" not in idle
assert "CortetsuPower.onBattery" in idle
assert "UPower.onBattery" not in idle
assert "IdleMonitor" in idle and 'action === "lock"' in idle
print("PASS: Cortetsu owns idle monitor policy and lock actions")
