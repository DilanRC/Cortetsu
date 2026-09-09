#!/usr/bin/env python3
"""Exercise the real persistent launcher with a disposable process."""

import os
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "cortetsu/bin/cortetsu-launch-persistent"
label = f"eval-{os.getpid()}"

runner = subprocess.Popen(
    [str(HELPER), "--label", label, "--working-directory", "/tmp", "--", "/usr/bin/sleep", "20"],
    stdout=subprocess.DEVNULL,
    stderr=subprocess.PIPE,
    text=True,
)
unit_prefix = f"cortetsu-app-{label}-"
unit = None
try:
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline and unit is None:
        result = subprocess.run(
            ["systemctl", "--user", "list-units", "--type=scope", "--all", "--no-legend", "--no-pager"],
            check=True,
            capture_output=True,
            text=True,
        )
        for line in result.stdout.splitlines():
            candidate = line.split(None, 1)[0]
            if candidate.startswith(unit_prefix) and candidate.endswith(".scope"):
                unit = candidate
                break
        if unit is None:
            time.sleep(0.05)

    assert unit is not None, runner.stderr.read()
    props = subprocess.run(
        ["systemctl", "--user", "show", unit, "-p", "ControlGroup", "--no-pager"],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    control_group = next(line.split("=", 1)[1] for line in props.splitlines() if line.startswith("ControlGroup="))
    cgroup_procs = Path("/sys/fs/cgroup", control_group.lstrip("/"), "cgroup.procs")
    pids = [int(value) for value in cgroup_procs.read_text(encoding="utf-8").split()]
    assert "/cortetsu-shell.service" not in control_group
    assert control_group.endswith(f"/{unit}")
    assert pids and all(Path(f"/proc/{pid}").exists() for pid in pids)
    print(f"Persistent launcher eval: {unit} isolated at {control_group}")
finally:
    if unit:
        subprocess.run(["systemctl", "--user", "stop", unit], check=True, capture_output=True)
    runner.wait(timeout=5)
