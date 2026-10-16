#!/usr/bin/env python3
"""cortetsu-power-auto asks power-profiles-daemon only on rule transitions.

The watcher used to run `powerprofilesctl get` (a Python interpreter) every
poll and put the rule's profile back over any profile picked by hand. A fake
powerprofilesctl on PATH records each call and holds the active profile.
"""
from __future__ import annotations

import importlib.util
import json
import os
import tempfile
from importlib.machinery import SourceFileLoader
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
FAKE = """#!/bin/sh
echo "$*" >> "$PPD_DIR/calls"
[ -f "$PPD_DIR/down" ] && exit 1
case "$1" in
  get) cat "$PPD_DIR/profile" ;;
  set) printf '%s\\n' "$2" > "$PPD_DIR/profile" ;;
esac
"""


def load(name: str, path: Path):
    loader = SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(name, loader)
    module = importlib.util.module_from_spec(spec)
    loader.exec_module(module)
    return module


with tempfile.TemporaryDirectory(prefix="cortetsu-power-auto-") as tmp:
    root = Path(tmp)
    (root / "bin").mkdir()
    (root / "bin/powerprofilesctl").write_text(FAKE)
    (root / "bin/powerprofilesctl").chmod(0o755)
    (root / "profile").write_text("balanced\n")
    os.environ.update(HOME=str(root), XDG_RUNTIME_DIR=str(root), PPD_DIR=str(root),
                      PATH=f"{root / 'bin'}:{os.environ['PATH']}")
    watcher = load("power_auto", REPO / "cortetsu/bin/cortetsu-power-auto")
    control = load("power_auto_control", REPO / "cortetsu/bin/cortetsu-power-auto-control")
    control.systemctl = lambda *args: control.subprocess.CompletedProcess(args, 0, "active\n", "")
    watcher.CONFIG_PATH.parent.mkdir(parents=True)
    watcher.CONFIG_PATH.write_text(json.dumps({"enabled": True, "ac_profile": "performance",
                                               "battery_profile": "balanced"}))
    source = {"ac": True}
    watcher.power_source = lambda: (source["ac"], 80.0, "Charging" if source["ac"] else "Discharging")

    def calls() -> list[str]:
        path = root / "calls"
        return path.read_text().splitlines() if path.exists() else []

    def profile() -> str:
        return (root / "profile").read_text().strip()

    def tick(settled: str, n: int = 1) -> str:
        for _ in range(n):
            keep, settled = watcher.iteration(settled=settled)
            assert keep
        return settled

    settled = tick("")
    assert profile() == "performance" and calls() == ["get", "set performance", "get"], calls()
    assert settled, "a verified profile settles the rule"

    settled = tick(settled, 20)
    assert len(calls()) == 3, f"a steady rule must not spawn powerprofilesctl: {calls()[3:]}"

    (root / "profile").write_text("power-saver\n")
    settled = tick(settled, 5)
    assert profile() == "power-saver", "a profile picked by hand survives while the rule is unchanged"
    assert len(calls()) == 3
    assert control.status()["last"]["profile"] == "power-saver", "the page reads the live profile"

    source["ac"] = False
    settled = tick(settled)
    assert profile() == "balanced" and settled, "an AC transition applies the battery rule"
    state = json.loads(watcher.STATE_PATH.read_text())
    assert state["ac_online"] is False and state["desired_profile"] == "balanced"

    source["ac"] = True
    (root / "down").touch()
    before = len(calls())
    settled = tick(settled, 2)
    assert settled == "" and len(calls()) == before + 2, "an unreachable daemon is retried, not marked applied"
    (root / "down").unlink()
    settled = tick(settled)
    assert profile() == "performance" and settled, "the retry applies once the daemon is back"

    # Both rules ask for the same profile: a hand pick must still end at the
    # next AC/battery transition, not survive it because the name matches.
    watcher.CONFIG_PATH.write_text(json.dumps({"enabled": True, "ac_profile": "balanced",
                                               "battery_profile": "balanced"}))
    settled = tick(settled)
    assert profile() == "balanced"
    (root / "profile").write_text("performance\n")
    settled = tick(settled, 3)
    assert profile() == "performance"
    source["ac"] = False
    settled = tick(settled)
    assert profile() == "balanced", "unplugging re-applies the battery rule even when its profile name is unchanged"

print("PASS: power-auto spawns powerprofilesctl only on rule transitions and keeps a hand-picked profile")
