from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")

assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
assert "Desktop context" in dash
assert "No active media" in dash
assert "Live context" in dash
assert "Weather" in dash
assert "Today" in dash and "Focus" in dash
assert "batterySubtitle" in dash and "networkSubtitle" in dash
assert "Icons.getBatteryIcon" in dash
assert "Layout.preferredWidth: 1.1" in dash
checks = {
    "host respects enabled and showDashboard": all(marker in host for marker in (
        "readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled",
        "CortetsuConfig.dashboard.showDashboard",
        "window.dashboardEnabled && window.screenState?.dashboard",
    )),
    "weather module is loadable": all(marker in dash for marker in (
        "active: root.showWeather",
        "Layout.preferredWidth: root.showWeather ? 1.35 : 0",
        "sourceComponent: weatherCard",
    )),
    "media module is loadable": all(marker in dash for marker in (
        "active: root.showMedia",
        "Layout.preferredWidth: root.showMedia ? 0.95 : 0",
        "sourceComponent: mediaCard",
    )),
    "performance module is loadable": "active: root.showPerformance" in dash and "sourceComponent: systemSummary" in dash,
    "all performance flags have consumers": all(f"active: root.show{name}" in dash for name in ("Cpu", "Gpu", "Memory", "Storage", "Battery", "Network")),
    "individual shortcut respects configuration": "CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts,
    "showall respects dashboard configuration": "state.dashboard = open && CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts,
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Dashboard modularity eval: {sum(checks.values())}/{len(checks)}")
print("PASS: Dashboard has a monitor-local Weather/Today/Focus/Media hierarchy with live system context")
