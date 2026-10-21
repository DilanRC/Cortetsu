#!/usr/bin/env python3
"""Runs fixture_CalendarPomodoroServices.qml under Quickshell in a private HOME.

The real cortetsu-pomodoro helper (linked into the private ~/.local/bin) runs
as the daemon the Pomodoro service owns; cortetsu-calendar is a stub that
writes a three-event cache. Nothing reads or writes the user's files, D-Bus or
compositor (offscreen platform). Also checks that the service starts exactly
one daemon and that it ends with the shell.
"""
from __future__ import annotations

import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

REPO = Path(__file__).resolve().parents[2]
FIXTURE = REPO / "cortetsu/tests/qml/services/fixture_CalendarPomodoroServices.qml"
# The real files under test, in a minimal runtime: Quickshell registers every
# singleton of an imported directory, and most shell services need Wayland.
RUNTIME_FILES = (
    "modules/CortetsuShellState.qml",
    "modules/calendar/CalendarService.qml",
    "modules/calendar/CalendarModel.js",
    "modules/pomodoro/Pomodoro.qml",
    "modules/pomodoro/PomodoroModel.js",
    "services/CortetsuToaster.qml",
)
CALENDAR_STUB = """#!/bin/sh
python3 - "$XDG_CACHE_HOME/cortetsu/calendar-events.json" <<'PY'
import json, sys
events = [{"eventId": f"e{i}", "calendarId": "c", "calendarName": "C", "title": f"S{i}",
           "start": "2026-10-20", "end": "2026-10-21", "allDay": True} for i in range(3)]
open(sys.argv[1], "w").write(json.dumps({"schema": 1, "calendars": [], "events": events}))
PY
echo '{"status":"ok"}'
"""


def daemons(home: Path) -> list[int]:
    found = []
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit():
            continue
        try:
            cmdline = (proc / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        if any(str(home).encode() in part for part in cmdline) and b"daemon" in cmdline:
            found.append(int(proc.name))
    return found


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="czp") as tmp:
        home = Path(tmp)
        bin_dir = home / ".local/bin"
        state = home / "state/cortetsu"
        for directory in (bin_dir, state, home / "cache/cortetsu", home / "config/cortetsu", home / "run"):
            directory.mkdir(parents=True)
        (home / "run").chmod(0o700)
        (bin_dir / "cortetsu-pomodoro").symlink_to(REPO / "cortetsu/bin/cortetsu-pomodoro")
        stub = bin_dir / "cortetsu-calendar"
        stub.write_text(CALENDAR_STUB)
        stub.chmod(0o755)
        # A user configuration and an announcement left by a previous shell.
        (state / "pomodoro.json").write_text(json.dumps({"schema": 2, "phase": "IDLE", "focusMinutes": 50}))
        (state / "pomodoro-notification.json").write_text(
            json.dumps({"sequence": time.time_ns() - 60_000_000_000, "title": "Antigua", "message": "no"}))
        env = {
            "PATH": "/usr/bin:/bin", "HOME": str(home), "XDG_STATE_HOME": str(home / "state"),
            "XDG_CACHE_HOME": str(home / "cache"), "XDG_CONFIG_HOME": str(home / "config"),
            "XDG_RUNTIME_DIR": str(home / "run"), "QT_QPA_PLATFORM": "offscreen",
            "DBUS_SESSION_BUS_ADDRESS": "unix:path=/nonexistent", "LANG": "C.UTF-8",
        }
        runtime = home / "runtime"
        for relative in RUNTIME_FILES:
            (runtime / relative).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(REPO / "cortetsu" / relative, runtime / relative)
        shutil.copyfile(FIXTURE, runtime / "shell.qml")
        shell = subprocess.Popen(["qs", "-p", str(runtime), "--no-color"], env=env, stdout=subprocess.PIPE,
                                 stderr=subprocess.STDOUT, text=True)
        seen = []
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and shell.poll() is None:
            seen.append(len(daemons(home)))
            if seen[-1]:
                break
            time.sleep(0.05)
        try:
            output, _ = shell.communicate(timeout=60)
        except subprocess.TimeoutExpired:
            shell.kill()
            output, _ = shell.communicate()
        print(output)
        assert "SERVICES_PASS" in output, "fixture failed"
        assert max(seen, default=0) == 1, f"expected exactly one Pomodoro daemon, saw {max(seen, default=0)}"
        end = time.monotonic() + 5
        while daemons(home) and time.monotonic() < end:
            time.sleep(0.05)
        assert not daemons(home), f"the daemon outlived the shell: {daemons(home)}"
        warnings = [line for line in output.splitlines() if " WARN" in line or "ERROR" in line]
        assert not warnings, warnings
    print("PASS: Calendar and Pomodoro services re-read their files, sync once, toast once and own one daemon")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
