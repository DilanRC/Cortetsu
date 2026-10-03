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
# The lock controller exposes requestLock(); it has no writable `locked` property.
assert idle.count("root.lock.requestLock()") == 2 and "lock.locked" not in idle
session = (repo / "cortetsu/services/CortetsuSession.qml").read_text(encoding="utf-8")
assert "signal aboutToSleep" in session and 'line.includes("boolean true")' in session
assert "function onAboutToSleep(): void" in idle and "if (CortetsuConfig.idleLockBeforeSleep)" in idle
assert '"--what=sleep", "--mode=delay"' in idle
assert "running: CortetsuConfig.idleLockBeforeSleep && !root.lock.lock.secure" in idle
print("PASS: Cortetsu owns idle monitor policy and lock actions")
