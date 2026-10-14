#!/usr/bin/env python3
"""NVIDIA vibrance: reading never runs nvibrant, writes send the full vector to the right display."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "cortetsu/bin/cortetsu-nvibrant"

# Mirrors nvibrant 1.3.0: each argument is a display value, omitted displays
# get 0, and the output echoes what it set. Every call is logged.
FAKE_NVIBRANT = r'''#!/usr/bin/env python3
import json, os, sys
from pathlib import Path
log = Path(os.environ["FAKE_NVIBRANT_LOG"])
calls = json.loads(log.read_text()) if log.exists() else []
calls.append(sys.argv[1:])
log.write_text(json.dumps(calls))
mode = os.environ.get("FAKE_NVIBRANT_MODE", "")
if mode == "fail":
    print("Failed to open /dev/nvidia-modeset device file for ioctl calls", file=sys.stderr)
    sys.exit(1)
kinds = os.environ.get("FAKE_NVIBRANT_DISPLAYS", "HDMI").split(",")
values = [int(value) for value in sys.argv[1:]]
print("Driver version: (615.71.09)\n")
for index, kind in enumerate(kinds):
    value = values[index] if index < len(values) else 0
    if mode == "clamp":
        value = min(value, 100)
    print(f"Display {index}:\n• ({index}, {kind}) • Set vibrance ({value:5d}) • None")
'''


def make_drm(root: Path, connectors: dict[str, tuple[str, str, int]]) -> None:
    """connectors: name -> (vendor, status, connector_id)."""
    for card_connector, (vendor, status, connector_id) in connectors.items():
        card = card_connector.split("-", 1)[0]
        (root / card / "device").mkdir(parents=True, exist_ok=True)
        (root / card / "device/vendor").write_text(vendor + "\n")
        (root / card_connector).mkdir()
        (root / card_connector / "status").write_text(status + "\n")
        (root / card_connector / "connector_id").write_text(f"{connector_id}\n")


class Fixture:
    def __init__(self, base: Path, connectors: dict[str, tuple[str, str, int]]):
        self.base = base
        self.drm = base / "drm"
        self.state = base / "state"
        self.log = base / "nvibrant-calls.json"
        self.bin = base / "bin"
        self.bin.mkdir(parents=True)
        make_drm(self.drm, connectors)
        fake = self.bin / "nvibrant"
        fake.write_text(FAKE_NVIBRANT)
        fake.chmod(0o755)
        (self.bin / "cortetsu-nvibrant").symlink_to(HELPER)
        self.env = dict(os.environ, CORTETSU_DRM_ROOT=str(self.drm), XDG_STATE_HOME=str(self.state),
                        XDG_CONFIG_HOME=str(base / "no-config"),
                        CORTETSU_NVIBRANT=str(fake), FAKE_NVIBRANT_LOG=str(self.log),
                        PATH=f"{self.bin}:{os.environ['PATH']}")

    def run(self, *args: str, **env: str) -> tuple[int, dict]:
        result = subprocess.run([str(HELPER), *args], text=True, capture_output=True,
                                env=dict(self.env, **env), timeout=20)
        return result.returncode, json.loads(result.stdout) if result.stdout.strip() else {}

    def calls(self) -> list[list[str]]:
        return json.loads(self.log.read_text()) if self.log.exists() else []

    def profile(self) -> dict:
        path = self.state / "cortetsu/nvibrant.json"
        return json.loads(path.read_text())["profile"] if path.exists() else {}


VICTUS = {"card1-HDMI-A-1": ("0x10de", "connected", 828),
          "card2-eDP-1": ("0x1002", "connected", 100),
          "card2-Writeback-1": ("0x1002", "connected", 101)}

with tempfile.TemporaryDirectory(prefix="cortetsu-nvibrant-") as temporary:
    base = Path(temporary)

    hdmi = Fixture(base / "hdmi", VICTUS)
    code, status = hdmi.run("status")
    assert code == 0 and status["conflict"] == "" and status["outputs"] == [
        {"connector": "HDMI-A-1", "card": "card1", "connected": True, "index": 0, "value": None}], status
    assert hdmi.calls() == [], "status must never run nvibrant: a bare call resets vibrance"

    for bad in ("1024", "-1025", "abc"):
        code, result = hdmi.run("set", "HDMI-A-1", bad)
        assert code == 1 and result["code"] == "value-invalid", result
    code, result = hdmi.run("set", "eDP-1", "200")
    assert code == 1 and result["code"] == "connector-unknown", "the AMD panel is not an NVIDIA output"
    assert hdmi.calls() == []

    code, result = hdmi.run("set", "HDMI-A-1", "-300")
    assert code == 0 and result == {"ok": True, "connector": "HDMI-A-1", "value": -300}
    assert hdmi.calls() == [["-300"]] and hdmi.profile() == {"HDMI-A-1": -300}

    code, result = hdmi.run("set", "HDMI-A-1", "500", FAKE_NVIBRANT_MODE="fail")
    assert code == 1 and result["code"] == "nvibrant-failed" and "ioctl" in result["error"]
    assert hdmi.profile() == {"HDMI-A-1": -300}, "a failed write must not change the profile"
    code, result = hdmi.run("set", "HDMI-A-1", "500", FAKE_NVIBRANT_MODE="clamp")
    assert code == 1 and result["code"] == "not-applied", result
    assert hdmi.profile() == {"HDMI-A-1": -300}

    code, result = hdmi.run("apply", "--default", "128")
    assert code == 0 and result["values"] == {"HDMI-A-1": -300}, "the saved profile wins over the default"
    assert hdmi.calls()[-1] == ["-300"]

    # A display order the helper did not predict is refused, not saved.
    code, result = hdmi.run("set", "HDMI-A-1", "50", FAKE_NVIBRANT_DISPLAYS="DP")
    assert code == 1 and result["code"] == "mapping-mismatch" and hdmi.profile() == {"HDMI-A-1": -300}

    # Two NVIDIA outputs: the write carries both values so neither is zeroed.
    multi = Fixture(base / "multi", dict(VICTUS, **{"card1-DP-1": ("0x10de", "connected", 830)}))
    assert multi.run("apply", "--default", "128", FAKE_NVIBRANT_DISPLAYS="HDMI,DP")[0] == 0
    assert multi.profile() == {"HDMI-A-1": 128, "DP-1": 128}
    code, _ = multi.run("set", "DP-1", "700", FAKE_NVIBRANT_DISPLAYS="HDMI,DP")
    assert code == 0 and multi.calls()[-1] == ["128", "700"], multi.calls()

    # card10 sorts after card2: display order is numeric, not lexical.
    cards = Fixture(base / "cards", {"card10-DP-1": ("0x10de", "connected", 5),
                                     "card2-HDMI-A-1": ("0x10de", "connected", 9)})
    assert [item["connector"] for item in cards.run("status")[1]["outputs"]] == ["HDMI-A-1", "DP-1"]

    # The pre-Cortetsu unit still enabled is reported, not hidden.
    legacy = Fixture(base / "legacy", VICTUS)
    wants = legacy.base / "config/systemd/user/graphical-session.target.wants"
    wants.mkdir(parents=True)
    (wants / "nvibrant.service").write_text("")
    assert legacy.run("status", XDG_CONFIG_HOME=str(legacy.base / "config"))[1]["conflict"] == "nvibrant.service"

    # Hotplug hook without an NVIDIA output: nothing runs, the dGPU stays asleep.
    unplugged = Fixture(base / "unplugged", dict(VICTUS, **{"card1-HDMI-A-1": ("0x10de", "disconnected", 828)}))
    code, result = unplugged.run("apply", "--default", "128")
    assert code == 0 and result == {"ok": True, "applied": False, "reason": "no-nvidia-output"}
    assert unplugged.calls() == []
    code, result = unplugged.run("set", "HDMI-A-1", "10")
    assert code == 1 and result["code"] == "connector-disconnected" and unplugged.calls() == []

    # The service the Settings page instantiates: opening it reads, never writes.
    qml = Fixture(base / "qml", VICTUS)
    assert qml.run("apply", "--default", "128")[0] == 0
    before = len(qml.calls())
    folder = base / "shell"
    folder.mkdir()
    shutil.copy(REPO / "cortetsu/services/Nvibrant.qml", folder / "Nvibrant.qml")
    (folder / "shell.qml").write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int stage: 0
    function fail(message) { console.error("NVIBRANT_FAIL", message); Qt.quit(); }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0) {
                if (!Nvibrant.available) return;
                if (Nvibrant.connector !== "HDMI-A-1" || !Nvibrant.known || Nvibrant.value !== 128
                    || Nvibrant.requested !== 128) return root.fail("status " + Nvibrant.value);
                console.log("NVIBRANT_OPENED");
                // A drag: only the last value has to land.
                Nvibrant.setValue(-2000);
                Nvibrant.setValue(400);
                Nvibrant.setValue(321.4);
                root.stage = 1;
            } else if (root.stage === 1) {
                if (Nvibrant.busy || Nvibrant.value !== 321) return;
                if (Nvibrant.requested !== 321 || Nvibrant.error.length) return root.fail("write " + Nvibrant.error);
                console.log("NVIBRANT_FIXTURE_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: root.fail("deadline") }
}
''')
    env = dict(qml.env, QT_QPA_PLATFORM="offscreen")
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml"), "--no-color"], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    assert "NVIBRANT_FIXTURE_PASS" in result.stdout and "NVIBRANT_FAIL" not in result.stdout, result.stdout
    calls = qml.calls()[before:]
    assert calls and calls[0] == ["-1024"], f"first write is the clamped minimum: {calls}"
    assert calls[-1] == ["321"] and all(len(call) == 1 for call in calls), calls
    assert len(calls) <= 2, f"a drag must coalesce to the latest value: {calls}"
    assert qml.profile() == {"HDMI-A-1": 321}
print("PASS: vibrance status never runs nvibrant; writes are validated, full-vector, confirmed and coalesced")
