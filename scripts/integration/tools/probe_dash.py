#!/usr/bin/env python3
import json, shutil, sys, tempfile, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import launcher_harness as H
def opened(s):
    d = json.loads(s.ipc("cortetsu-shell", "inspect").stdout); return [e["surface"] for e in d["open_states"]]
with tempfile.TemporaryDirectory(prefix="cz-dash-", dir="/tmp") as tmp:
    s = H.Session(Path(tmp))
    (s.home/'.config/cortetsu').mkdir(parents=True, exist_ok=True)
    shutil.copy(Path.home()/'.config/cortetsu/preferences.json', s.home/'.config/cortetsu/preferences.json')
    try:
        s.start(outputs=2); mon = s.headless()[0]; s.focus_monitor(mon); time.sleep(1)
        s.start_client(); time.sleep(1.5)
        m = next(x for x in s.monitors() if x["name"] == mon); W, Hh = m["width"], m["height"]
        X = m["x"] + W // 2
        s.move(X, m["y"] + Hh // 2); time.sleep(0.5)
        for y in range(Hh // 2, -1, -20):  # glide up like a hand would
            s.move(X, m["y"] + max(0, y)); time.sleep(0.01)
        s.move(X, m["y"]); time.sleep(0.15); print("at edge 150ms", opened(s), flush=True)
        time.sleep(0.6); print("at edge 750ms", opened(s), flush=True)
        for y in (5, 20, 60, 120, 200):
            s.move(X, m["y"] + y); time.sleep(0.4); print("down", y, opened(s), flush=True)
        print(s.hyprctl("layers"))
    finally:
        s.stop()
