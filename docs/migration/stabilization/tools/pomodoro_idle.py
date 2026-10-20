#!/usr/bin/env python3
"""Idle cost of a cortetsu-pomodoro daemon: wakeups, CPU and RSS over N seconds.

    python3 docs/migration/stabilization/tools/pomodoro_idle.py HELPER SECONDS [focus]

Runs HELPER daemon against a private XDG_STATE_HOME (IDLE state, or a focus
phase ending after the window with `focus`) and reports voluntary context
switches (each one a wakeup), CPU time and RSS from /proc.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time


def proc_status(pid: int) -> dict[str, int]:
    fields = {}
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        key, _, value = line.partition(":")
        if key in ("voluntary_ctxt_switches", "VmRSS"):
            fields[key] = int(value.split()[0])
    stat = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
    fields["cpu_ticks"] = int(stat[11]) + int(stat[12])
    return fields


helper, seconds = sys.argv[1], float(sys.argv[2])
phase = sys.argv[3] if len(sys.argv) > 3 else "idle"
with tempfile.TemporaryDirectory() as tmp:
    state = Path(tmp) / "cortetsu"
    state.mkdir()
    payload = {"schema": 2, "phase": "IDLE"}
    if phase == "focus":
        payload = {"schema": 2, "phase": "FOCUS", "targetEndTimestamp": time.time() + seconds + 600}
    (state / "pomodoro.json").write_text(json.dumps(payload))
    daemon = subprocess.Popen([sys.executable, helper, "daemon"], env={**os.environ, "XDG_STATE_HOME": tmp})
    try:
        time.sleep(1.0)  # start-up
        before = proc_status(daemon.pid)
        time.sleep(seconds)
        after = proc_status(daemon.pid)
    finally:
        daemon.terminate()
        daemon.wait(5)
ticks = os.sysconf("SC_CLK_TCK")
print(json.dumps({
    "helper": helper, "phase": phase, "seconds": seconds,
    "wakeups": after["voluntary_ctxt_switches"] - before["voluntary_ctxt_switches"],
    "cpu_ms": round((after["cpu_ticks"] - before["cpu_ticks"]) * 1000 / ticks, 1),
    "rss_kib": after["VmRSS"],
}))
