#!/usr/bin/env python3
"""DisplayVibrance.qml writes the latest value of every output it was given.

A slider drag outruns the shader rebuild, so writes queue while one runs.
Moving a second output mid-write must not drop the first output's value,
and a status read must not undo values still waiting to be written.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SERVICE = REPO / "cortetsu/services/DisplayVibrance.qml"

# Each set takes long enough for the fixture to queue behind it.
FAKE_HELPER = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
log = Path(os.environ["FAKE_VIBRANCE_LOG"])
args = sys.argv[1:]
if args == ["status"]:
    profile = json.loads(log.read_text())["profile"] if log.exists() else {}
    print(json.dumps({"ok": True, "active": True, "default": 16, "minimum": -100, "maximum": 100,
                      "outputs": [{"id": 0, "name": n, "value": profile.get(n, 16)}
                                  for n in ("eDP-1", "HDMI-A-1")]}))
    sys.exit(0)
if args[:1] == ["set"]:
    state = json.loads(log.read_text()) if log.exists() else {"calls": [], "profile": {}}
    state["calls"].append([args[1], int(args[2])])
    time.sleep(0.3)
    state["profile"][args[1]] = int(args[2])
    log.write_text(json.dumps(state))
    print(json.dumps({"ok": True, "name": args[1], "value": int(args[2])}))
    sys.exit(0)
sys.exit(2)
'''

SHELL = r'''import QtQuick
import Quickshell
import "services"

ShellRoot {
    property int step: 0
    Timer {
        interval: 100
        repeat: true
        running: true
        onTriggered: {
            const v = DisplayVibrance;
            if (step === 0 && v.hasOutput("eDP-1") && v.hasOutput("HDMI-A-1")) {
                v.setValue("eDP-1", 40);
                v.setValue("HDMI-A-1", 30);
                v.setValue("eDP-1", 50);
                // A status read now must not undo the queued values.
                v.reload();
                step = 1;
            } else if (step === 1 && v.valueFor("eDP-1") !== 50) {
                console.log(`VIBRANCE_FAIL queued value lost on screen: ${v.valueFor("eDP-1")}`);
                Qt.quit();
            } else if (step === 1 && !v.busy && Object.keys(v.pending).length === 0) {
                console.log(`VIBRANCE_DONE ${JSON.stringify(v.values)} ${v.error}`);
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.log("VIBRANCE_FAIL timeout"); Qt.quit(); } }
}
'''


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-vibrance-service-") as tmp:
        root = Path(tmp)
        (root / "config/services").mkdir(parents=True)
        shutil.copy(SERVICE, root / "config/services/DisplayVibrance.qml")
        (root / "config/shell.qml").write_text(SHELL)
        (root / "bin").mkdir()
        helper = root / "bin/cortetsu-display-vibrance"
        helper.write_text(FAKE_HELPER)
        helper.chmod(0o755)
        log = root / "calls.json"
        env = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}", FAKE_VIBRANCE_LOG=str(log),
                   QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(root / "no-config"))
        result = subprocess.run(["qs", "-p", str(root / "config/shell.qml"), "--no-color"],
                                env=env, text=True, capture_output=True, timeout=20)
        output = result.stdout + result.stderr
        assert "VIBRANCE_DONE" in output and "VIBRANCE_FAIL" not in output, output
        state = json.loads(log.read_text())
        assert state["calls"] == [["eDP-1", 40], ["HDMI-A-1", 30], ["eDP-1", 50]], state["calls"]
        assert state["profile"] == {"eDP-1": 50, "HDMI-A-1": 30}, state["profile"]
        done = next(line for line in output.splitlines() if "VIBRANCE_DONE" in line)
        assert '"eDP-1":50' in done and '"HDMI-A-1":30' in done, done
    print("PASS: queued saturation writes keep every output's latest value")


if __name__ == "__main__":
    main()
