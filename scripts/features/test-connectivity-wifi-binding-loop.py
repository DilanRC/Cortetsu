"""ConnectivityWifi must not mutate `operation` while `operationConnected` notifies.

A change of the observed network's `connected` used to call observe()
synchronously; observe() reassigns `operation`, which `operationConnected`
depends on, so Qt reported a binding loop and skipped that re-evaluation.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="cortetsu-wifi-loop-test-") as temporary:
    root = Path(temporary)
    for name in ("ConnectivityWifi.qml", "ConnectivityNmAdapter.qml", "ConnectivityPolicy.js"):
        shutil.copy(repo / "cortetsu/services" / name, root / name)
    # Inert nmcli: the adapter must not reach the real NetworkManager.
    binary = root / "nmcli"
    binary.write_text("#!/bin/sh\n[ \"$1\" = monitor ] && exec sleep 60\nexit 0\n")
    binary.chmod(0o700)
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
import "."
import "ConnectivityPolicy.js" as Policy
ShellRoot {
    readonly property var wifi: ConnectivityWifi
    QtObject {
        id: before
        property bool connected: false
        property int state: 0
        property var device: null
        signal connectionFailed(int reason)
    }
    QtObject {
        id: fake
        property bool connected: true
        property int state: 0
        property var device: null
        signal connectionFailed(int reason)
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            // A connect whose network left the list: observe() fails it.
            wifi.operationNetwork = before;
            wifi.operation = Policy.operation(1, "connect", {}, "connecting", Date.now());
            // operationConnected flips false -> true through the network
            // reference itself, so only its change handler sees it.
            wifi.operationNetwork = fake;
            Qt.callLater(() => {
                if (wifi.operation.state === "failed" && wifi.operation.lastErrorCode === "ap-unavailable")
                    console.log("WIFI_LOOP_DONE");
                else
                    console.error("FAIL", "operation not observed: " + JSON.stringify(wifi.operation));
                Qt.quit();
            });
        }
    }
}
''')
    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", QT_QPA_PLATFORM="offscreen")
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(root / "shell.qml"), "--no-color"], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    out = result.stdout
    assert "WIFI_LOOP_DONE" in out and "FAIL" not in out, out
    assert "Binding loop" not in out, out
print("PASS: ConnectivityWifi observes operationConnected without a binding loop")
