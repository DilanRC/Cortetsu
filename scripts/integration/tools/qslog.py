#!/usr/bin/env python3
"""Start the nested shell, run one IPC call and print QML warnings."""
import json, sys, tempfile, time
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import launcher_harness as H
with tempfile.TemporaryDirectory(prefix="cz-log-", dir="/tmp") as tmp:
    s = H.Session(Path(tmp))
    try:
        s.start(); time.sleep(2)
        print("ipc", s.ipc(*sys.argv[1:]).returncode)
        for t in range(6):
            print(t, s.ipc("drawers", "isOpen", "dashboard").stdout.strip(), flush=True); time.sleep(0.3)
        print("open", [e["surface"] for e in json.loads(s.ipc("cortetsu-shell", "inspect").stdout)["open_states"]])
        for line in (s.logs / "qs.log").read_text(errors="replace").splitlines():
            if any(k in line for k in ("WARN scene", "WARN qml", "ERROR", "TypeError", "ReferenceError", "is not a type", "Cannot assign")) or "qml" in line and "WARN" in line:
                print(line[:300])
    finally:
        s.stop()
