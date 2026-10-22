#!/usr/bin/env python3
"""Semantic parity with the shipped Python CLI in isolated XDG directories.

These test-only archived sources preserve the prior observable behavior. It performs no operations on the real user's HOME or session.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PYTHON = ROOT / "tests/reference/python-runtime/cortetsu/bin/cortetsu-notifications"
RUST = ROOT / "cortetsu/notification-helper/target/release/cortetsu-notifications-rs"


def run(cmd: list[str], env: dict[str, str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                          timeout=10, check=False)


def parse_output(raw: str, action: list[str]):
    if action[0] == "history" and raw.strip():
        return json.loads(raw)
    return raw.strip()


def read_state(root: Path) -> dict:
    result = {}
    for name in ("notifs.json", "notification-status.json"):
        file = root / "cortetsu" / name
        if not file.exists():
            result[name] = None
        else:
            text = file.read_text(encoding="utf-8")
            try:
                result[name] = json.loads(text)
                if name == "notification-status.json" and isinstance(result[name], dict):
                    # New durable transaction metadata is additive, not user content.
                    result[name].pop("revision", None)
                    result[name].pop("manual_override_until_unix_ms", None)
            except json.JSONDecodeError:
                result[name] = {"invalid_raw": text}
    return result


def verify(seed: dict, actions: list[list[str]]) -> None:
    with tempfile.TemporaryDirectory(prefix="cortetsu-notifications-parity-") as parent:
        base = Path(parent)
        p, r = base / "python", base / "rust"
        for root in (p, r):
            folder = root / "cortetsu"
            folder.mkdir(parents=True)
            for name, payload in seed.items():
                (folder / name).write_text(payload, encoding="utf-8")
        for argv in actions:
            environ = os.environ.copy()
            environ.pop("PYTHONPATH", None)
            python = run([sys.executable, str(PYTHON), *argv], {**environ, "XDG_STATE_HOME": str(p)})
            rust = run([str(RUST), *argv], {**environ, "XDG_STATE_HOME": str(r)})
            assert python.returncode == rust.returncode, (argv, python.returncode, rust.returncode, python.stderr, rust.stderr)
            assert parse_output(python.stdout, argv) == parse_output(rust.stdout, argv), (argv, python.stdout, rust.stdout)
            # The Rust implementation may choose safer permissions and JSON formatting,
            # but must preserve observable state without removing extra fields.
            if not any(file == "notifs.json" and payload.startswith("{broken") for file, payload in seed.items()):
                assert read_state(p) == read_state(r), (argv, read_state(p), read_state(r))


def main() -> None:
    assert RUST.is_file(), f"Rust binary absent: {RUST}"
    seed = {
        "notifs.json": json.dumps([
            {"notificationId": 42, "id": 1, "summary": "Reunión 日本", "body": "privado"},
            {"id": 8, "summary": "Aviso 2", "markup": "conservar"},
            {"id": "abc", "summary": "String ID"},
        ]),
        "notification-status.json": json.dumps({"dnd": False, "custom": 5}),
    }
    verify(seed, [["count"], ["history"], ["dismiss", "42"], ["history"],
                  ["dismiss", "8"], ["dnd", "status"], ["dnd", "on"],
                  ["dnd", "toggle"], ["dnd", "off"], ["clear"], ["count"]])
    verify({}, [["count"], ["history"], ["dnd", "status"], ["clear"], ["history"]])
    verify({"notifs.json": "{broken history"}, [["count"], ["clear"], ["count"]])
    # Deliberate safety change: the old CLI reset corrupt status. The native
    # owner refuses it without overwriting bytes; this is not a parity waiver.
    with tempfile.TemporaryDirectory(prefix="cortetsu-corrupt-owner-") as parent:
        target = Path(parent) / "cortetsu" / "notification-status.json"
        target.parent.mkdir()
        target.write_text("{invalid")
        for action in (["dnd", "status"], ["dnd", "on"]):
            result = run([str(RUST), *action], {**os.environ, "XDG_STATE_HOME": parent})
            assert result.returncode != 0 and target.read_text() == "{invalid"
    verify({}, [["unknown"], ["dnd", "unknown"]])
    print("PASS: Rust notifications CLI semantic parity (private XDG_STATE_HOME)")


if __name__ == "__main__":
    main()
