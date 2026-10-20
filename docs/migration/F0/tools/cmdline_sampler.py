#!/usr/bin/env python3
"""Log user processes whose cmdline contains a needle (default: the string the
wallpaper watcher treats as 'Wallpaper Engine running'). Usage: sampler.py SECONDS out.log"""
import os, sys, time
from pathlib import Path
needle = ("linux-" + "wallpaperengine").encode()  # split so this sampler never matches itself
sec, out = float(sys.argv[1]), open(sys.argv[2], "w")
seen = set(); t0 = time.monotonic()
while time.monotonic() - t0 < sec:
    for e in Path("/proc").iterdir():
        if e.name.isdigit() and e.name not in seen:
            try:
                c = (e / "cmdline").read_bytes()
                if needle in c and e.stat().st_uid == os.getuid():
                    seen.add(e.name); print(round(time.monotonic()-t0, 2), e.name, c.replace(b"\0", b" ")[:200].decode(errors="replace"), file=out, flush=True)
            except OSError: pass
    time.sleep(0.05)
