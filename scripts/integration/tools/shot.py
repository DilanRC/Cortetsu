#!/usr/bin/env python3
"""Screenshot the nested shell on a headless output.

shot.py OUT.png [ipc target method [args...]]
"""
import subprocess, sys, tempfile, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import launcher_harness as H
out = sys.argv[1]
with tempfile.TemporaryDirectory(prefix="cz-shot-", dir="/tmp") as tmp:
    s = H.Session(Path(tmp))
    try:
        s.start(outputs=2)
        mon = s.headless()[0]
        s.focus_monitor(mon)
        time.sleep(1)
        s.start_client()
        time.sleep(1.5)
        if len(sys.argv) > 3:
            s.ipc(*sys.argv[2:])
            time.sleep(1.5)
        print("grim", subprocess.run(["grim", "-o", mon, out], env=s.env(), timeout=15).returncode, flush=True)
    finally:
        s.stop()
