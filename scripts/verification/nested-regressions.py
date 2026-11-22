#!/usr/bin/env python3
"""Runtime checks that need a nested Hyprland, run on a free workspace.

    python3 scripts/verification/nested-regressions.py [--workspace N] [LOGDIR]

Each check starts its own Hyprland with an isolated HOME, config and runtime
directory; none touches the desktop's compositor, preferences or
generations, and none submits a password (the lock check uses
pam_permit/pam_deny stacks). The nested windows are born on one workspace
through scripts/integration/ws2_run.py, so focus and the active workspace
never move.

Without --workspace the first empty workspace of eDP-1 is used, never 2 (where
Dilan works) and never the active one. With none free it stops before
starting anything.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CHECKS = (
    "test-cortetsu-lock-runtime.py",
    "test-cortetsu-idle-runtime.py",
    "test-gamemode-runtime.py",
    "test-keybind-editor-runtime.py",
    "test-orbital-nested-playback.py",
    "test-cortetsu-hub-fullscreen-nested.py",
)


def hypr(*args: str):
    return json.loads(subprocess.run(["hyprctl", *args, "-j"], text=True, capture_output=True, check=True).stdout)


def free_workspace() -> int | None:
    active = hypr("activeworkspace")["id"]
    for workspace in sorted(hypr("workspaces"), key=lambda w: w["id"]):
        if (workspace["monitor"] == "eDP-1" and workspace["windows"] == 0
                and workspace["id"] not in (2, active) and workspace["id"] > 0):
            return workspace["id"]
    return None


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=int)
    parser.add_argument("logdir", nargs="?")
    options = parser.parse_args()
    workspace = options.workspace or free_workspace()
    if workspace is None or workspace == 2:
        print("ERROR: no free eDP-1 workspace (other than 2 and the active one)", file=sys.stderr)
        return 2
    logs = Path(options.logdir or tempfile.mkdtemp(prefix="cortetsu-nested-"))
    logs.mkdir(parents=True, exist_ok=True)
    failed = []
    for check in CHECKS:
        log = logs / f"{check}.log"
        code = subprocess.run([sys.executable, str(ROOT / "scripts/integration/ws2_run.py"), "--workspace", str(workspace),
                               "--timeout", "900", str(log), "--", sys.executable, str(ROOT / "scripts/features" / check)]).returncode
        last = (log.read_text(errors="replace").strip().splitlines() or [""])[-1]
        print(f"{'PASS' if code == 0 else 'FAIL'} {check}: {last[:200]}")
        if code != 0:
            failed.append(check)
    print(f"logs: {logs}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
