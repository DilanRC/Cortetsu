import re
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
modules = repo / "cortetsu/modules"
network = (modules / "CortetsuNetwork.qml").read_text(encoding="utf-8")
idle = (modules / "CortetsuIdleInhibitor.qml").read_text(encoding="utf-8")
hub = (modules / "BottomHub.qml").read_text(encoding="utf-8")

# Network status is DBus-driven via Quickshell's native NetworkManager binding:
# no nmcli, no Process/Timer polling, no Caelestia dependency.
backend = (repo / "cortetsu/services/ConnectivityWifi.qml").read_text(encoding="utf-8")
assert "import Quickshell.Networking" in backend
assert "ConnectivityWifi.active" in network
for marker in ("activeEthernet", "strength", "ssid", "DeviceType", "ConnectionState", "connecting"):
    assert marker in network + backend, marker
for banned in ("nmcli", "Quickshell.Io", "Process {", "Timer {", "monitor", "GlobalConfig", "Caelestia"):
    assert banned not in network, banned

for marker in ("IdleInhibitor", "PersistentProperties", "cortetsu-idle-inhibitor"):
    assert marker in idle, marker
assert "Services.IdleInhibitor" not in hub
assert not re.search(r"(?<!Cortetsu)Nmcli\.", hub)
for marker in ("CortetsuNetwork.active", "CortetsuIdleInhibitor.enabled"):
    assert marker in hub, marker
print("PASS: Bottom Hub network and idle state use Cortetsu contracts")
