#!/usr/bin/env python3
"""Behavioural regressions for cortetsu-notifications (history + DND actions)."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HELPER = Path(__file__).resolve().parents[2] / "cortetsu/bin/cortetsu-notifications"


def run(env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(HELPER), *args],
        env=env,
        capture_output=True,
        text=True,
        timeout=5,
        check=False,
    )


with tempfile.TemporaryDirectory() as directory:
    env = {**os.environ, "XDG_STATE_HOME": directory}
    state_dir = Path(directory) / "cortetsu"

    # Missing files: count/history/dnd all resolve to safe empty defaults.
    result = run(env, "count")
    assert result.returncode == 0 and result.stdout.strip() == "0", result

    result = run(env, "history")
    assert result.returncode == 0 and json.loads(result.stdout) == [], result

    result = run(env, "dnd", "status")
    assert result.returncode == 0 and result.stdout.strip() == "off", result

    # Seed two history entries as the live shell (upstream Notifs.qml) would.
    state_dir.mkdir(parents=True, exist_ok=True)
    seeded = [
        {"notificationId": 1, "summary": "First", "urgency": 1, "actions": []},
        {"notificationId": 2, "summary": "Second", "urgency": 2, "actions": ["Open"]},
    ]
    (state_dir / "notifs.json").write_text(json.dumps(seeded), encoding="utf-8")

    result = run(env, "count")
    assert result.stdout.strip() == "2", result

    result = run(env, "history")
    parsed = json.loads(result.stdout)
    assert [entry["notificationId"] for entry in parsed] == [1, 2], parsed

    # Dismiss one entry by id; only that entry is removed from the snapshot.
    result = run(env, "dismiss", "1")
    assert result.returncode == 0 and result.stdout.strip() == "1", result
    remaining = json.loads((state_dir / "notifs.json").read_text(encoding="utf-8"))
    assert [entry["notificationId"] for entry in remaining] == [2], remaining
    assert sorted(path.name for path in state_dir.iterdir()) == ["notifs.json"], "partial write left behind"

    # A half-written file is not an empty history: Notifs.qml would close every
    # live notification missing from a rewritten [], so dismiss must refuse.
    (state_dir / "notifs.json").write_text('[{"notificationId": 2', encoding="utf-8")
    result = run(env, "dismiss", "2")
    assert result.returncode == 65, result
    assert (state_dir / "notifs.json").read_text(encoding="utf-8") == '[{"notificationId": 2', "file rewritten"
    (state_dir / "notifs.json").write_text(json.dumps(remaining), encoding="utf-8")

    # Dismissing an id that no longer exists is a safe no-op.
    result = run(env, "dismiss", "999")
    assert result.returncode == 0 and result.stdout.strip() == "1", result

    # Clear empties the snapshot entirely.
    result = run(env, "clear")
    assert result.returncode == 0 and result.stdout.strip() == "0", result
    assert json.loads((state_dir / "notifs.json").read_text(encoding="utf-8")) == []

    # DND toggles and persists across invocations.
    result = run(env, "dnd", "toggle")
    assert result.stdout.strip() == "on", result
    assert json.loads((state_dir / "notification-status.json").read_text(encoding="utf-8"))["dnd"] is True

    result = run(env, "dnd", "status")
    assert result.stdout.strip() == "on", result

    result = run(env, "dnd", "off")
    assert result.stdout.strip() == "off", result

    result = run(env, "dnd", "bogus")
    assert result.returncode == 64, result

    result = run(env)
    assert result.returncode == 64, result

print("PASS: cortetsu-notifications owns history dismiss/clear and DND state deterministically")
