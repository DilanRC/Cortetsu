from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
for marker in ('name: "dashboard"', "WlrLayer.Overlay", "ShellState.forActive()", "Dash", "screenState.dashboard"):
    assert marker in host, marker
for marker in ("NOW", "NOW PLAYING", "SYSTEM", "Cpu.percentage", "Memory.percentage", "Players.active", "CortetsuSurface"):
    assert marker in dash, marker
assert "visible: false" in panels
assert "DashboardHost {}" in shell
print("PASS: Dashboard is a first-party full surface with live context and legacy panel consumer disabled")
