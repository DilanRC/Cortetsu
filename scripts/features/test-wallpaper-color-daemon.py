#!/usr/bin/env python3
"""The wallpaper colour watcher re-colours only when a source changes.

Drives the real daemon with --once against a fake /proc, a fake
cortetsu-apply-wallpaper-colors that records its argument, and real state
files, through: first start, steady state, Wallpaper Engine starting and
stopping, a new static path and the same file rewritten in place.
"""
import json
import os
import subprocess
import tempfile
from pathlib import Path

DAEMON = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-wallpaper-color-daemon"

with tempfile.TemporaryDirectory(prefix="cortetsu-wallcolor-") as tmp:
    home = Path(tmp)
    proc = home / "proc"
    (proc / "1").mkdir(parents=True)
    (proc / "1/cmdline").write_bytes(b"/usr/bin/bash\0wallpaper-engine-render-daemon\0")
    bindir = home / ".local/bin"
    bindir.mkdir(parents=True)
    (bindir / "cortetsu-apply-wallpaper-colors").write_text(f'#!/bin/sh\necho "$1" >> {home}/applied\n')
    (bindir / "cortetsu-apply-wallpaper-colors").chmod(0o755)
    wall_a, wall_b = home / "a.png", home / "b.png"
    wall_a.write_bytes(b"a")
    wall_b.write_bytes(b"b")
    state = home / ".local/state/cortetsu/wallpaper/path.txt"
    state.parent.mkdir(parents=True)
    state.write_text(f"{wall_a}\n")
    engine = home / ".config/Linux Wallpaper Engine/active-wallpapers.json"
    engine.parent.mkdir(parents=True)
    engine.write_text(json.dumps({"activeWallpapers": {"eDP-1": {"backgroundId": 123}}}))
    env = {**os.environ, "HOME": str(home), "XDG_RUNTIME_DIR": str(home), "CORTETSU_PROC_ROOT": str(proc)}
    env.pop("XDG_STATE_HOME", None)

    def once() -> list[str]:
        subprocess.run(["python3", str(DAEMON), "--once"], env=env, check=True, timeout=20)
        applied = home / "applied"
        return applied.read_text().splitlines() if applied.exists() else []

    assert once() == [str(wall_a)], "first start colours the static wallpaper"
    assert once() == [str(wall_a)], "an unchanged source spawns nothing"

    (proc / "4242").mkdir()
    (proc / "4242/cmdline").write_bytes(b"linux-wallpaperengine\0--screen-root\0eDP-1\0")
    assert once() == [str(wall_a)], "Wallpaper Engine owns the colours while it runs"
    engine.write_text(json.dumps({"activeWallpapers": {"eDP-1": {"backgroundId": 456}}}))
    assert once() == [str(wall_a)], "a scene change under Wallpaper Engine does not touch the static scheme"

    (proc / "4242/cmdline").unlink()
    (proc / "4242").rmdir()
    assert once() == [str(wall_a)] * 2, "stopping Wallpaper Engine restores the static wallpaper's colours"

    state.write_text(f"{wall_b}\n")
    assert once()[-1] == str(wall_b), "a path written by another tool is coloured"
    wall_b.write_bytes(b"bb-rewritten")
    assert len(once()) == 4, "the same file rewritten in place is coloured again"
    assert len(once()) == 4

    lock = (home / "cortetsu-wallpaper-color-daemon/lock").open("a")
    import fcntl
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    state.write_text(f"{wall_a}\n")
    assert len(once()) == 4, "a second instance exits while the first holds the lock"

print("PASS: the wallpaper colour watcher re-colours exactly on source changes and spawns nothing otherwise")
