from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
today = (ROOT / "cortetsu/modules/dashboard/Today.qml").read_text(encoding="utf-8")
focus = (ROOT / "cortetsu/modules/dashboard/Focus.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")

for marker in ('name: "dashboard"', "WlrLayer.Overlay", "CortetsuShellState.forScreen(modelData)", "Dash", "screenState.dashboard"):
    assert marker in host, marker
assert "CortetsuShellState.forActive()" not in host
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
assert 'CortetsuPower.onBattery' in dash and 'CortetsuPower.charging' in dash
assert "Icons.getBatteryIcon" in dash

# Dashboard settings must change the composition, not only persist in the
# settings file. Loaders keep disabled modules out of the live provider tree.
for marker in (
    "readonly property bool showWeather: CortetsuConfig.dashboard.showWeather",
    "readonly property bool showMedia: CortetsuConfig.dashboard.showMedia",
    "readonly property bool showPerformance: CortetsuConfig.dashboard.showPerformance",
    "readonly property bool showCpu: showPerformance && CortetsuConfig.dashboard.performance.showCpu",
    "readonly property bool showGpu: showPerformance && CortetsuConfig.dashboard.performance.showGpu",
    "readonly property bool showMemory: showPerformance && CortetsuConfig.dashboard.performance.showMemory",
    "readonly property bool showStorage: showPerformance && CortetsuConfig.dashboard.performance.showStorage",
    "readonly property bool showNetwork: showPerformance && CortetsuConfig.dashboard.performance.showNetwork",
    "readonly property bool showBattery: showPerformance && CortetsuConfig.dashboard.performance.showBattery",
    "sourceComponent: weatherCard",
    "sourceComponent: mediaCard",
    "sourceComponent: systemSummary",
):
    assert marker in dash, marker
assert "readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled" in host
assert "CortetsuConfig.dashboard.showDashboard" in host
assert "state.dashboard = open && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts
assert "CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts

assert "visible: false" in panels
assert "DashboardHost {}" in shell
print("PASS: Dashboard is monitor-local and first-party with live Today, Focus, media, system, power and network context")
