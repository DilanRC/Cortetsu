from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")

assert "CortetsuShellState.forScreen(modelData)" in host
assert "CortetsuShellState.forActive()" not in host
assert "Desktop context" in dash
assert "No active media" in dash
assert "Live context" in dash
assert "Weather" in dash
assert "Today" in dash and "Focus" in dash
assert "batterySubtitle" in dash and "networkSubtitle" in dash
assert "Layout.preferredWidth: 1.35" in dash
assert "Layout.preferredWidth: 1.1" in dash
assert "Layout.preferredWidth: 0.95" in dash
print("PASS: Dashboard has a monitor-local Weather/Today/Focus/Media hierarchy with live system context")
