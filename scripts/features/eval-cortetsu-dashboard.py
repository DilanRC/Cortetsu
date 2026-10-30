from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
# The dashboard is Dash.qml plus its Dash*.qml pieces.
dash = "\n".join(p.read_text(encoding="utf-8") for p in sorted((ROOT / "cortetsu/modules/dashboard").glob("Dash*.qml")))
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")

assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
# H-22: honest empty states and readings without a fake action.
assert "Tiempo no disponible" in dash and "Nada en reproducción" in dash
assert "CortetsuListRow" not in dash
assert "Weather" in dash
assert "Today" in dash and "Focus" in dash
checks = {
    "host respects enabled and showDashboard": all(marker in host for marker in (
        "readonly property bool dashboardEnabled: CortetsuConfig.dashboard.enabled",
        "CortetsuConfig.dashboard.showDashboard",
        "window.dashboardEnabled && (screenState?.dashboard ?? false)",
    )),
    "zones follow the settings": all(marker in dash for marker in (
        "enabled: CortetsuConfig.dashboard.showMedia",
        "enabled: CortetsuConfig.dashboard.showPerformance",
        "enabled: CortetsuConfig.dashboard.showWeather",
    )),
    "only the current zone is loaded": "active: root.open" in dash and 'root.currentKey === "performance" ? performanceZone' in dash,
    "every gauge follows its flag": all(f"CortetsuConfig.dashboard.performance.show{name}" in dash for name in ("Cpu", "Gpu", "Memory", "Storage", "Battery", "Network")),
    "individual shortcut respects configuration": "CortetsuConfig.dashboard.enabled && CortetsuConfig.dashboard.showDashboard" in shortcuts,
}
assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Dashboard modularity eval: {sum(checks.values())}/{len(checks)}")
print("PASS: Dashboard has a monitor-local Weather/Today/Focus/Media hierarchy with live system context")
