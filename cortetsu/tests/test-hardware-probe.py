#!/usr/bin/env python3
"""The hardware probe trims only the process list when asked to."""
import json
import os
import subprocess
import tempfile
from pathlib import Path

PROBE = Path(__file__).resolve().parents[1] / "bin/cortetsu-hardware-probe"
SECTIONS = {"timestamp", "host", "kernel", "uptime_sec", "load", "cpu", "memory", "disk", "disk_io",
            "disks_io", "battery", "network", "gpus", "fans", "processes", "process_count"}


def sample(runtime: str, *args: str) -> tuple[dict, int]:
    result = subprocess.run(["python3", str(PROBE), *args], capture_output=True, text=True, timeout=30,
                            env={**os.environ, "XDG_RUNTIME_DIR": runtime})
    assert result.returncode == 0, result.stderr
    return json.loads(result.stdout), len(result.stdout)


with tempfile.TemporaryDirectory(prefix="cortetsu-hardware-probe-") as runtime:
    full, full_size = sample(runtime)
    trimmed, trimmed_size = sample(runtime, "--top-processes", "5")

    assert set(full) == SECTIONS, sorted(set(full) ^ SECTIONS)
    assert set(trimmed) == SECTIONS, sorted(set(trimmed) ^ SECTIONS)
    assert len(full["processes"]) == full["process_count"] > 5, full["process_count"]
    assert len(trimmed["processes"]) == 5, len(trimmed["processes"])
    assert trimmed["process_count"] > 5, "the count still covers every scanned process"
    assert trimmed["processes"] == sorted(
        trimmed["processes"], key=lambda p: (-p["cpu"], -p["mem"], p["name"].lower())), "most active first"
    assert trimmed_size * 4 < full_size, (trimmed_size, full_size)

    # The trimmed run still records every process, so the next full sample has deltas for all of them.
    state = json.loads((Path(runtime) / "cortetsu-hardware-probe-state.json").read_text())
    assert len(state["process_ticks"]) >= trimmed["process_count"] - 50, len(state["process_ticks"])

    rejected = subprocess.run(["python3", str(PROBE), "--top-processes", "many"], capture_output=True, text=True,
                              env={**os.environ, "XDG_RUNTIME_DIR": runtime})
    assert rejected.returncode != 0 and not rejected.stdout, "a malformed count is refused, not guessed"

print(f"PASS: the probe trims the process list on request ({full_size} -> {trimmed_size} bytes)")
