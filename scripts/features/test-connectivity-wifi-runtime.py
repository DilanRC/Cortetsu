"""Exercise adapter queues and profile confirmation with an isolated nmcli fixture."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="cortetsu-connectivity-test-") as temporary:
    root = Path(temporary)
    for name in ("ConnectivityWifi.qml", "ConnectivityNmAdapter.qml", "ConnectivityPolicy.js"):
        shutil.copy(repo / "cortetsu/services" / name, root / name)
    state = root / "fixture.json"
    state.write_text(json.dumps({"profiles": ["12345678-abcd-1234-abcd-123456789012", "12345678-abcd-1234-abcd-123456789013"], "autoconnect": True, "ipv4": {"method": "auto", "addresses": "", "gateway": "", "dns": "", "ignore-auto-dns": "no"}}))
    binary = root / "nmcli"
    binary.write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
assert "example-only-passphrase" not in " ".join(args)
state = Path(os.environ["CONNECTIVITY_FIXTURE"])
data = json.loads(state.read_text())
if args == ["monitor"]:
    while True: time.sleep(60)
if "wifi" in args and "radio" in args: print("enabled")
elif "delete" in args:
    data["profiles"].remove(args[-1]); state.write_text(json.dumps(data))
elif "add" in args:
    data["profiles"].append(args[args.index("connection.uuid") + 1]); state.write_text(json.dumps(data))
elif "modify" in args:
    if "ipv4.method" in args:
        for key in data["ipv4"]: data["ipv4"][key] = args[args.index("ipv4." + key) + 1]
    else: data["autoconnect"] = args[-1] == "yes"
    state.write_text(json.dumps(data))
elif "up" in args:
    if "passwd-file" in args:
        assert sys.stdin.read() == "802-11-wireless-security.psk:example-only-passphrase\\n"
        data["passwordReceived"] = True; state.write_text(json.dumps(data))
elif "device" in args and "wifi" in args:
    print("*:AA\\\\:BB\\\\:CC\\\\:DD\\\\:EE\\\\:FF: Same SSID :82:5180 MHz:WPA2:wlan0")
    print(":AA\\\\:BB\\\\:CC\\\\:DD\\\\:EE\\\\:00: Same SSID :42:2412 MHz:WPA2:wlan0")
elif "device" in args:
    print("GENERAL.DEVICE:wlan0\\nGENERAL.CON-UUID:12345678-abcd-1234-abcd-123456789012\\nGENERAL.CONNECTION:Different profile name\\nIP4.ADDRESS[1]:192.0.2.1/24\\nIP4.DNS[1]:192.0.2.53")
elif "uuid" in args:
    print("802-11-wireless.ssid: Same SSID \\nconnection.interface-name:wlan0")
    for key, value in data["ipv4"].items(): print("ipv4." + key + ":" + value)
else:
    for uuid in data["profiles"]: print(uuid + ":Different profile name:802-11-wireless:" + ("yes" if data["autoconnect"] else "no") + ":")
''')
    binary.chmod(0o700)
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int step: 0
    ConnectivityNmAdapter {
        id: hidden
        onMutationFinished: (operationId, success, code, message, retryable) => {
            if (operationId === 77) {
                if (!root.check(success, "hidden activation fixture failed: " + message)) return;
                console.log("PASS_HIDDEN", "PSK delivered only via closed stdin pipe");
                console.log("PASS_ADAPTER", "UUID operations and IPv4 confirmed, gone targets, multiple BSSID, whitespace");
                Qt.quit();
            }
        }
    }
    readonly property var wifi: ConnectivityWifi
    Component.onCompleted: console.log("TEST_STARTED", wifi.operation.state)
    function check(condition, message) {
        if (!condition) { console.error("FAIL", message); Qt.quit(); }
        return condition;
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (root.step === 0) {
                if (root.wifi.profiles.length !== 2 || !root.wifi.profiles[0].ssid || root.wifi.accessPoints.length !== 2) return;
                if (!root.check(root.wifi.profiles[0].ssid === " Same SSID ", "SSID whitespace lost")) return;
                if (!root.check(root.wifi.accessPoints[0].bssid !== root.wifi.accessPoints[1].bssid, "BSSID collapsed")) return;
                root.wifi.forgetProfile("12345678-abcd-1234-abcd-123456789012");
                if (!root.check(root.wifi.operation.state === "forgetting", "forget optimistic completion")) return;
                root.step = 1;
            } else if (root.step === 1) {
                if (root.wifi.operation.state !== "idle") return;
                if (!root.check(root.wifi.profiles.length === 1, "forget not confirmed by UUID inventory")) return;
                root.wifi.setAutoconnect("12345678-abcd-1234-abcd-123456789013", false);
                if (!root.check(root.wifi.operation.state === "changing", "autoconnect optimistic completion")) return;
                root.step = 2;
            } else if (root.step === 2) {
                if (root.wifi.operation.state !== "idle") return;
                if (!root.check(!root.wifi.profiles[0].autoconnect, "autoconnect not confirmed")) return;
                root.wifi.setIpv4("12345678-abcd-1234-abcd-123456789013", "manual", "192.0.2.2/24", "192.0.2.254", "192.0.2.53");
                if (!root.check(root.wifi.operation.state === "changing", "IPv4 optimistic completion")) return;
                root.step = 3;
            } else if (root.step === 3) {
                if (root.wifi.operation.state !== "idle") return;
                if (!root.check(root.wifi.profiles[0].ipv4.method === "manual", "IPv4 not confirmed")) return;
                root.wifi.connectNetwork(null, "", null);
                if (!root.check(root.wifi.operation.state === "failed" && root.wifi.operation.lastErrorCode === "ap-unavailable", "gone native target not handled")) return;
                hidden.createHidden(77, "12345678-abcd-1234-abcd-123456789014", "Hidden Fixture", "wlan0", "wpa-psk", "example-only-passphrase");
                root.step = 4;
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.error("FAIL", "adapter test deadline"); Qt.quit(); } }
}
''')
    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", CONNECTIVITY_FIXTURE=str(state), QT_QPA_PLATFORM="offscreen")
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(root / "shell.qml"), "--no-color"], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=18)
    assert result.returncode == 0 and "PASS_ADAPTER" in result.stdout and "FAIL" not in result.stdout, result.stdout
    assert "TypeError" not in result.stdout and "ReferenceError" not in result.stdout and " WARN" not in result.stdout, result.stdout
    processes = subprocess.run(["ps", "-eo", "args"], text=True, stdout=subprocess.PIPE, check=True).stdout
    assert str(binary) not in processes, "fixture nmcli process survived shell exit"
    assert len(json.loads(state.read_text())["profiles"]) == 2
    assert json.loads(state.read_text())["passwordReceived"] is True
    assert "PASS_HIDDEN" in result.stdout
    assert "example-only-passphrase" not in result.stdout
print("PASS: isolated nmcli runtime verifies profile operations without touching user profiles")
