#!/usr/bin/env python3
"""cortetsu-pomodoro: phases, persistence, notifications and the daemon.

Clock-dependent cases pass `now` explicitly. The daemon case runs the real
helper against a private XDG_STATE_HOME and never touches the user's state.
"""
from __future__ import annotations

import fcntl
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from importlib.machinery import SourceFileLoader
from pathlib import Path

helper = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-pomodoro"
spec = importlib.util.spec_from_loader("pomodoro", SourceFileLoader("pomodoro", str(helper)))
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)
NOW = 1_000_000.0


def event() -> dict:
    return json.loads(module.event_path().read_text(encoding="utf-8"))


def wait_for(predicate, timeout: float = 5.0) -> bool:
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return True
        time.sleep(0.05)
    return predicate()


def check_phases() -> None:
    state = module.load()
    assert state["phase"] == "IDLE" and state["schema"] == 2

    state = module.advance({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW - 1}, NOW)
    assert state["phase"] == "BREAK" and state["completedSessions"] == 1
    assert state["targetEndTimestamp"] == NOW + 5 * 60

    state = module.advance({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW - 1,
                            "completedSessions": 3}, NOW)
    assert state["phase"] == "LONG_BREAK" and state["completedSessions"] == 4
    assert state["targetEndTimestamp"] == NOW + state["longBreakMinutes"] * 60

    state["targetEndTimestamp"] = NOW - 1
    state = module.advance(state, NOW)
    assert state["phase"] == "FOCUS"

    # Pause keeps the remaining time; resume restores it from a new now.
    state = module.apply_command({**state, "targetEndTimestamp": NOW + 600}, "pause", NOW)
    assert state["phase"] == "PAUSED" and state["pausedPhase"] == "FOCUS" and state["pausedRemainingMs"] == 600_000
    later = NOW + 3600  # time spent paused does not count
    state = module.apply_command(state, "resume", later)
    assert state["phase"] == "FOCUS" and state["targetEndTimestamp"] == later + 600

    # Pausing a break resumes the break, not a focus session.
    state = module.apply_command({**module.DEFAULT, "phase": "BREAK", "targetEndTimestamp": NOW + 60}, "pause", NOW)
    assert module.apply_command(state, "resume", NOW)["phase"] == "BREAK"

    assert module.apply_command({**module.DEFAULT, "phase": "LONG_BREAK", "targetEndTimestamp": NOW + 30},
                                "skip", NOW)["phase"] == "FOCUS"
    # Skip only applies to breaks; pause only to running phases.
    focus = {**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW + 30}
    assert module.apply_command(focus, "skip", NOW) == module.normalize_state(focus)
    assert module.apply_command(module.DEFAULT, "pause", NOW)["phase"] == "IDLE"
    try:
        module.apply_command(module.DEFAULT, "bogus", NOW)
        raise AssertionError("unknown command accepted")
    except ValueError:
        pass


def check_reset_keeps_configuration() -> None:
    custom = {**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW + 60, "completedSessions": 7,
              "focusMinutes": 50, "shortBreakMinutes": 10, "longBreakMinutes": 30, "sessionsBeforeLongBreak": 3}
    state = module.apply_command(custom, "reset", NOW)
    assert state["phase"] == "IDLE" and state["completedSessions"] == 0 and state["targetEndTimestamp"] == 0
    assert (state["focusMinutes"], state["shortBreakMinutes"], state["longBreakMinutes"],
            state["sessionsBeforeLongBreak"]) == (50, 10, 30, 3)
    assert module.apply_command(state, "start", NOW)["targetEndTimestamp"] == NOW + 50 * 60


def check_invalid_and_clock_changes() -> None:
    # Corrupt or impossible states recover instead of sticking.
    assert module.normalize_state("garbage")["phase"] == "IDLE"
    assert module.normalize_state({"phase": "FOCUS", "targetEndTimestamp": 0})["phase"] == "IDLE"
    assert module.normalize_state({"phase": "FOCUS", "targetEndTimestamp": "x"})["phase"] == "IDLE"
    assert module.normalize_state({"phase": "PAUSED", "pausedPhase": "IDLE"})["pausedPhase"] == "FOCUS"
    assert module.normalize_state({"focusMinutes": -4, "completedSessions": "x"})["focusMinutes"] == 1

    # Clock set back two hours during a focus session: at most a full phase remains.
    state = module.advance({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW + 600}, NOW - 7200)
    assert state["phase"] == "FOCUS" and state["targetEndTimestamp"] == NOW - 7200 + 25 * 60
    # Clock moved forward past the end (or a suspend): the phase ends once, on wake.
    state = module.advance({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW + 600}, NOW + 86400)
    assert state["phase"] == "BREAK" and state["completedSessions"] == 1
    assert state["targetEndTimestamp"] == NOW + 86400 + 300
    # Timestamps are UTC seconds: the time zone does not move the deadline.
    original = os.environ.get("TZ")
    try:
        for zone in ("UTC", "America/Costa_Rica", "Asia/Kolkata"):
            os.environ["TZ"] = zone
            time.tzset()
            assert module.advance({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW + 60},
                                  NOW)["targetEndTimestamp"] == NOW + 60
    finally:
        if original is None:
            os.environ.pop("TZ", None)
        else:
            os.environ["TZ"] = original
        time.tzset()


def check_settle_notifies_once() -> None:
    module.ensure_event_file()
    assert event() == {"sequence": 0}
    expired = {**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": NOW - 1}
    module.save(expired)
    with module.state_lock():
        first = module.settle(module.load(), NOW)
    announced = event()
    assert first["phase"] == "BREAK" and announced["title"] == "Sesión de concentración completada"
    with module.state_lock():
        second = module.settle(module.load(), NOW + 1)
    assert second == first and event() == announced, "a second settle announced the same phase end again"
    assert module.load() == first

    # A command that notices an ended phase announces it too (before: only the
    # daemon wrote events, so a click at the deadline lost the notification).
    module.save({**module.DEFAULT, "phase": "BREAK", "targetEndTimestamp": NOW - 1})
    state = module.run_command("pause", NOW)
    assert state["phase"] == "PAUSED" and state["pausedPhase"] == "FOCUS"
    assert event()["title"] == "Descanso terminado"

    # status does not rewrite an unchanged state.
    before = module.path().stat().st_mtime_ns
    time.sleep(0.01)
    module.run_command("status", NOW)
    assert module.path().stat().st_mtime_ns == before


def check_persistence_compatibility() -> None:
    # A schema-2 file written by the previous helper loads unchanged.
    legacy = {"schema": 2, "phase": "PAUSED", "targetEndTimestamp": 0.0, "pausedRemainingMs": 123456,
              "pausedPhase": "LONG_BREAK", "completedSessions": 8, "focusMinutes": 45, "shortBreakMinutes": 5,
              "longBreakMinutes": 20, "sessionsBeforeLongBreak": 4}
    module.path().write_text(json.dumps(legacy, indent=2) + "\n", encoding="utf-8")
    assert module.load() == legacy
    module.save(legacy)
    assert json.loads(module.path().read_text(encoding="utf-8")) == legacy
    assert oct(module.path().stat().st_mode & 0o777) == "0o600"
    assert not list(module.path().parent.glob(".pomodoro.json.tmp.*"))


def check_daemon(directory: str) -> None:
    env = {**os.environ, "XDG_STATE_HOME": directory}
    env.pop("CORTETSU_POMODORO_STATE", None)

    # A second daemon exits at once while the lock is held.
    lock_path = module.daemon_lock_path()
    with lock_path.open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        result = subprocess.run([sys.executable, str(helper), "daemon"], env=env, timeout=5, check=False)
        assert result.returncode == 0

    module.save(module.DEFAULT)
    module.write_event("old", "event")
    daemon = subprocess.Popen([sys.executable, str(helper), "daemon"], env=env)
    try:
        assert wait_for(lambda: lock_path.read_text().strip() == str(daemon.pid)), "daemon did not publish its PID"

        # Idle: the daemon sleeps instead of polling.
        status = Path(f"/proc/{daemon.pid}/status")
        switches = lambda: int(next(l for l in status.read_text().splitlines()
                                    if l.startswith("voluntary_ctxt_switches")).split()[1])
        before = switches()
        time.sleep(2.0)
        assert switches() - before <= 1, f"idle daemon woke {switches() - before} times in 2 s"

        # A command moves the deadline; the daemon is woken and announces the end on time.
        sequence = event()["sequence"]
        module.save({**module.DEFAULT, "phase": "FOCUS", "targetEndTimestamp": time.time() + 0.6})
        module.wake_daemon()
        assert wait_for(lambda: event()["sequence"] != sequence, timeout=5), "phase end not announced"
        assert event()["title"] == "Sesión de concentración completada"
        assert module.load()["phase"] == "BREAK"
        assert daemon.poll() is None
    finally:
        daemon.send_signal(signal.SIGTERM)
        daemon.wait(5)
    # Without a daemon, waking is a no-op.
    module.wake_daemon()


with tempfile.TemporaryDirectory() as directory:
    state_path = Path(directory) / "cortetsu/pomodoro.json"
    state_path.parent.mkdir(parents=True)
    module.path = lambda: state_path
    check_phases()
    check_reset_keeps_configuration()
    check_invalid_and_clock_changes()
    check_settle_notifies_once()
    check_persistence_compatibility()
    check_daemon(directory)

print("PASS: Pomodoro phases, reset, clock changes, single notifications, persistence and idle daemon")
