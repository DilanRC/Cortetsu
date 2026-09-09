from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
host = (ROOT / "cortetsu/modules/DashboardHost.qml").read_text(encoding="utf-8")
dash = (ROOT / "cortetsu/modules/dashboard/Dash.qml").read_text(encoding="utf-8")
panels = (ROOT / "cortetsu/modules/drawers/Panels.qml").read_text(encoding="utf-8")
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")

for marker in ('name: "dashboard"', "WlrLayer.Overlay", "CortetsuShellState.forActive()", "Dash", "screenState.dashboard"):
    assert marker in host, marker
for marker in ("NOW", "NOW PLAYING", "SYSTEM", "Cpu.percentage", "Memory.percentage", "Players.active", "CortetsuSurface"):
    assert marker in dash, marker

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
print("PASS: Dashboard is first-party and keeps battery/power semantics separate from network context")
