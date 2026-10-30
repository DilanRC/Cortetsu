from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
today = (ROOT / "cortetsu/modules/dashboard/Today.qml").read_text(encoding="utf-8")
focus = (ROOT / "cortetsu/modules/dashboard/Focus.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")

for marker in ('name: "dashboard"', "WlrLayer.Overlay", "CortetsuShellState.forScreen(modelData)", "DashboardLayer", "screenState?.dashboard"):
    assert marker in host, marker
assert "CortetsuShellState.forActive()" not in host
# Four zones in one fixed frame hanging from the top edge, as in caelestia.
for marker in ('qsTr("Inicio")', 'qsTr("Multimedia")', 'qsTr("Rendimiento")', 'qsTr("Clima")',
               "screenState.dashboardTab = index", "Keys.onLeftPressed", "Keys.onRightPressed",
               "Cpu.percentage", "Memory.percentage", "Players.active", "Today", "Focus",
               "NetworkUsage.downloadSpeed", "Weather.hourlyForecast", "Weather.forecast"):
    assert marker in dash, marker
layer = (ROOT / "cortetsu/modules/dashboard/DashboardLayer.qml").read_text(encoding="utf-8")
assert "anchors.top: parent.top" in layer and "anchors.horizontalCenter: parent.horizontalCenter" in layer
assert "anchors.centerIn: parent" not in layer.split("Dash {")[1]
# Only the current zone is loaded, and only while open: telemetry samples
# only while the Rendimiento zone is on screen.
assert "active: root.open" in dash
assert "Cpu.consumers += 1" in dash and "Cpu.consumers -= 1" in dash

# Today is a live, read-only agenda projection over Cortetsu's calendar cache,
# through the Calendar's own service and date rules.
service = (ROOT / "cortetsu/modules/calendar/CalendarService.qml").read_text(encoding="utf-8")
for marker in ("CalendarService.events", "todayEvents", "CalendarModel.eventsOn",
               'OverlayPolicy.open(CortetsuShellState.allStates(), screenState, "calendar")'):
    assert marker in today, marker
assert "calendar-events.json" in service and "watchChanges: true" in service and "onFileChanged: reload()" in service
assert "FileView" not in today
assert "root.todayEvents.slice(0, 2)" in today
assert "No hay eventos hoy" in today
# Events carry `title` (cortetsu-calendar normalize_event); there is no `summary`.
assert "modelData.title ||" in today and "modelData.summary" not in today

# Focus reuses the persistent first-party Pomodoro state/helper instead of
# inventing a dashboard-only timer.
pomodoro_service = (ROOT / "cortetsu/modules/pomodoro/Pomodoro.qml").read_text(encoding="utf-8")
pomodoro_model = (ROOT / "cortetsu/modules/pomodoro/PomodoroModel.js").read_text(encoding="utf-8")
for marker in ("pomodoro.json", "cortetsu-pomodoro", "watchChanges: true"):
    assert marker in pomodoro_service, marker
for marker in ("targetEndTimestamp", "pausedRemainingMs"):
    assert marker in pomodoro_model, marker
assert "completedSessions" in focus and "Pomodoro.state" in focus
for command in ('return state?.phase === "PAUSED" ? "resume" : "start";', 'return "pause";'):
    assert command in pomodoro_model, command
assert "Pomodoro.run(root.command)" in focus
assert 'Pomodoro.run(Model.isBreak(root.pomodoro.phase) ? "skip" : "reset")' in focus
assert "FileView" not in focus and "function runPomodoro" not in focus

# Battery and network: their own facts, never the SSID as a battery subtitle.
assert 'CortetsuNetwork.active?.ssid ?? qsTr("Sin conexión")' in dash
assert 'CortetsuPower.onBattery' in dash and 'CortetsuPower.charging' in dash
# Settings change the composition: disabled zones and gauges disappear.
for marker in ("CortetsuConfig.dashboard.showMedia", "CortetsuConfig.dashboard.showPerformance",
               "CortetsuConfig.dashboard.showWeather", "performance.showCpu", "performance.showGpu", "performance.showMemory",
               "performance.showStorage", "performance.showNetwork", "performance.showBattery"):
    assert marker in dash, marker
assert "readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled" in host
assert "CortetsuConfig.dashboard.showDashboard" in host
assert "CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts

assert "visible: false" in panels
assert "DashboardHost {}" in shell
print("PASS: Dashboard is monitor-local and first-party with four zones: Inicio, Multimedia, Rendimiento and Clima")
