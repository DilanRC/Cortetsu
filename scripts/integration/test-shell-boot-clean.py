#!/usr/bin/env python3
"""Boot the whole shell in a nested Hyprland and open every drawer once.

Offscreen cannot load PanelWindow, so this is the check that a type, import or
file the shell needs at run time still exists: after deleting base/ code, a
missing file only shows up here, as "is not a type" or "Type ... unavailable"
in the Quickshell log.

Run it on a free workspace of eDP-1, never on the one in use:

    python3 scripts/integration/ws2_run.py --workspace 4 LOG -- \
        python3 scripts/integration/test-shell-boot-clean.py
"""
from __future__ import annotations

from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

MARKERS = ("is not a type", "unavailable", "ReferenceError", "TypeError", "Binding loop",
           "Unable to assign", "Failed to load configuration", "No such file")

missing = H.missing_tools()
if missing:
    print(f"SKIP: missing {', '.join(missing)}")
    sys.exit(0)

with tempfile.TemporaryDirectory(prefix="czb") as tmp:
    session = H.Session(Path(tmp))
    try:
        try:
            session.start()
        except AssertionError as error:
            # Session.start also waits for launcher layers, which times out on
            # the pre-phase-3 tree too; the QML load is what is checked here.
            print(f"note: {error}; checking the load log only")
        drawers = [name for name in session.ipc("drawers", "list").stdout.split() if name]
        for name in drawers:
            session.ipc("drawers", "toggle", name)
            time.sleep(1.2)
            if session.ipc("drawers", "isOpen", name).stdout.strip() == "1":
                session.ipc("drawers", "toggle", name)
                time.sleep(0.4)
        log = (session.logs / "qs.log").read_text(errors="replace")
    finally:
        session.stop()

assert "Configuration Loaded" in log, log[-3000:]
bad = sorted({line.strip() for line in log.splitlines() if any(marker in line for marker in MARKERS)})
assert not bad, "\n".join(bad)
print(f"PASS: the shell loads and opens {len(drawers)} drawers ({', '.join(drawers)}) without QML errors")
