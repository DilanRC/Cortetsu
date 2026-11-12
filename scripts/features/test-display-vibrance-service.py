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
    if int(args[2]) == 99:
        # The entry point disappears (a broken link during an install).
        Path(sys.argv[0]).unlink()
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
            } else if (Quickshell.env("VIBRANCE_SCENARIO") === "vanish") {
                // The first write removes the helper; the second cannot start.
                if (step === 1 && v.valueFor("eDP-1") === 50 && !v.busy) {
                    v.setValue("eDP-1", 99);
                    step = 2;
                } else if (step === 2 && !v.busy) {
                    v.setValue("HDMI-A-1", 5);
                    step = 3;
                } else if (step === 3 && !v.busy && v.error.length > 0) {
                    console.log("VIBRANCE_DONE unstartable helper frees the queue");
                    Qt.quit();
                }
            } else if (step === 1 && v.valueFor("eDP-1") !== 50) {
                console.log(`VIBRANCE_FAIL queued value lost on screen: ${v.valueFor("eDP-1")}`);
                Qt.quit();
            } else if (step === 1 && v.writes.idle) {
                console.log(`VIBRANCE_DONE ${JSON.stringify(v.values)} ${v.error}`);
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.log(`VIBRANCE_FAIL timeout at step ${step}: ${JSON.stringify(DisplayVibrance.values)} ${DisplayVibrance.error}`); Qt.quit(); } }
}
'''


def main() -> None:
    queue()
    vanish()
    print("PASS: queued saturation writes keep every output's latest value; an unstartable helper frees the queue")


def vanish() -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-vibrance-service-") as tmp:
        output, _ = launch(Path(tmp), VIBRANCE_SCENARIO="vanish")
        assert "unstartable helper frees the queue" in output and "VIBRANCE_FAIL" not in output, output


def launch(root: Path, **extra: str) -> tuple[str, Path]:
    (root / "config/services").mkdir(parents=True)
    shutil.copy(SERVICE, root / "config/services/DisplayVibrance.qml")
    shutil.copy(SERVICE.with_name("HelperWriteQueue.qml"), root / "config/services/HelperWriteQueue.qml")
    (root / "config/shell.qml").write_text(SHELL)
    (root / "bin").mkdir()
    helper = root / "bin/cortetsu-display-vibrance"
    helper.write_text(FAKE_HELPER)
    helper.chmod(0o755)
    log = root / "calls.json"
    # System directories only: the installed helper in ~/.local/bin must
    # never stand in for the fake one, least of all once it is removed.
    env = dict(os.environ, PATH=f"{root / 'bin'}:/usr/bin:/bin", FAKE_VIBRANCE_LOG=str(log),
               QT_QPA_PLATFORM="offscreen", XDG_CONFIG_HOME=str(root / "no-config"), **extra)
    result = subprocess.run(["qs", "-p", str(root / "config/shell.qml"), "--no-color"],
                            env=env, text=True, capture_output=True, timeout=60)
    return result.stdout + result.stderr, log


def queue() -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-vibrance-service-") as tmp:
        output, log = launch(Path(tmp))
        assert "VIBRANCE_DONE" in output and "VIBRANCE_FAIL" not in output, output
        state = json.loads(log.read_text())
        assert state["calls"] == [["eDP-1", 40], ["HDMI-A-1", 30], ["eDP-1", 50]], state["calls"]
        assert state["profile"] == {"eDP-1": 50, "HDMI-A-1": 30}, state["profile"]
        done = next(line for line in output.splitlines() if "VIBRANCE_DONE" in line)
        assert '"eDP-1":50' in done and '"HDMI-A-1":30' in done, done


if __name__ == "__main__":
    main()
