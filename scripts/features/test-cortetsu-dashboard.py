from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
today = (ROOT / "cortetsu/modules/dashboard/Today.qml").read_text(encoding="utf-8")
focus = (ROOT / "cortetsu/modules/dashboard/Focus.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ('name: "dashboard"', "WlrLayer.Overlay", "CortetsuShellState.forActive()", "Dash", "screenState.dashboard"):
    assert marker in host, marker
for marker in ("NOW", "NOW PLAYING", "SYSTEM", "Cpu.percentage", "Memory.percentage", "Players.active", "CortetsuSurface", "Today", "Focus"):
    assert marker in dash, marker
assert 'icon: "close"' in dash
assert "onClicked: root.screenState.dashboard = false" in dash

# Today is a live, read-only agenda projection over Cortetsu's calendar cache.
for marker in ("calendar-events.json", "todayEvents", "eventOccursOnDay", "watchChanges: true", 'setRetained("calendar", true)'):
    assert marker in today, marker
assert "root.todayEvents.slice(0, 2)" in today
assert "No events today" in today

# Focus reuses the persistent first-party Pomodoro state/helper instead of
# inventing a dashboard-only timer.
for marker in ("pomodoro.json", "cortetsu-pomodoro", "targetEndTimestamp", "pausedRemainingMs", "completedSessions", "watchChanges: true"):
    assert marker in focus, marker
for command in ('runPomodoro("start")', 'runPomodoro("pause")', 'runPomodoro("resume")'):
    assert command in focus, command
assert 'runPomodoro(root.isBreakPhase(root.pomodoro.phase) ? "skip" : "reset")' in focus

# Battery and network are distinct live-context contracts. The old dashboard
# incorrectly used the active Wi-Fi SSID as the battery subtitle.
for marker in ("batteryCharging", "batteryPercent", "batterySubtitle", "networkTitle", "networkSubtitle"):
    assert marker in dash, marker
assert 'subtitle: root.batterySubtitle' in dash
assert 'subtitle: root.networkSubtitle' in dash
assert 'title: root.networkTitle' in dash
assert 'CortetsuNetwork.active?.ssid ?? qsTr("Offline")' in dash
assert 'subtitle: CortetsuNetwork.active?.ssid ?? qsTr("Network unavailable")' not in dash
assert 'UPower.onBattery' in dash and 'UPowerDeviceState.Charging' in dash

assert "visible: false" in panels
assert "DashboardHost {}" in shell
print("PASS: Dashboard is first-party with live Today, Focus, media, system, power and network context")
