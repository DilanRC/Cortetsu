#!/usr/bin/env python3
"""Schema-2 helper ownership/readback regressions on a private XDG sandbox.

No shell, real helper, systemd service, or user homedir is modified.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
SYSTEM = REPO / "core/system.py"
DOTFILES = REPO / "core/dotfiles.py"


def run(env: dict[str, str], tool: Path, *args: str, ok: bool = True) -> str:
    result = subprocess.run(
        [sys.executable, str(tool), *args, "--repo", str(REPO)],
        cwd=REPO, env=env, text=True, capture_output=True, check=False,
    )
    if (result.returncode == 0) != ok:
        raise AssertionError(f"{tool.name} {' '.join(args)}: {result.returncode}: {result.stdout}{result.stderr}")
    return result.stdout + result.stderr


def atomic_pointer(link: Path, target: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    candidate = link.with_name(link.name + ".new")
    candidate.symlink_to(target, target_is_directory=True)
    candidate.replace(link)


def bundle(root: Path, name: str, content: bytes) -> Path:
    path = root / "helpers/builds" / name
    path.mkdir(parents=True)
    helper = path / "cortetsu-test-helper"
    helper.write_bytes(content)
    helper.chmod(0o700)
    (path / "HELPERS.json").write_text(json.dumps({
        "schema": 1,
        "build_id": name,
        "helpers": [{"name": helper.name, "bytes": len(content), "sha256": hashlib.sha256(content).hexdigest()}],
    }) + "\n", encoding="utf-8")
    return path


with tempfile.TemporaryDirectory(prefix="cortetsu-schema2-") as temp:
    base = Path(temp)
    home = base / "home"
    data = base / "data"
    runtime = base / "runtime"
    home.mkdir()
    runtime.mkdir()
    env = os.environ.copy()
    env.update(HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
               CORTETSU_DATA_ROOT=str(data), CORTETSU_RUNTIME_ROOT=str(runtime))
    shell = data / "builds/shell-test"
    shell.mkdir(parents=True)
    for filename, content in {"shell.qml": "// fixture\n", "BUILD_ID": "shell-test\n", "BUILD.json": '{"schema":1}\n'}.items():
        (shell / filename).write_text(content, encoding="utf-8")
    atomic_pointer(runtime / "current", shell)
    run(env, DOTFILES, "apply")
    run(env, SYSTEM, "promote")
    baseline = (data / "system/current").resolve(strict=True)

    helpers = bundle(data, "helpers-test-1", b"#!/bin/sh\necho one\n")
    atomic_pointer(data / "helpers/current", helpers)
    system = data / "system/builds/schema2-test"
    system.mkdir()
    old = json.loads((baseline / "SYSTEM.json").read_text(encoding="utf-8"))
    old.update(schema=2, helpersGeneration=str(helpers))
    (system / "SYSTEM.json").write_text(json.dumps(old) + "\n", encoding="utf-8")
    atomic_pointer(data / "system/previous", baseline)
    atomic_pointer(data / "system/current", system)
    assert "PASS: system generation" in run(env, SYSTEM, "verify")
    assert "previous_helpers" not in run(env, SYSTEM, "status")
    assert "current_helpers" in run(env, SYSTEM, "status")
    assert "schema boundary" in run(env, SYSTEM, "rollback", ok=False)

    # A helper edit or owner drift must be detected before reporting success.
    (helpers / "cortetsu-test-helper").write_bytes(b"#!/bin/sh\necho two\n")
    assert "digest mismatch" in run(env, SYSTEM, "verify", ok=False)
    (helpers / "cortetsu-test-helper").write_bytes(b"#!/bin/sh\necho one\n")
    assert "PASS: system generation" in run(env, SYSTEM, "verify")
    different = bundle(data, "helpers-test-2", b"#!/bin/sh\necho two\n")
    atomic_pointer(data / "helpers/current", different)
    assert "helpers drift" in run(env, SYSTEM, "verify", ok=False)
    atomic_pointer(data / "helpers/current", helpers)
    assert "PASS: system generation" in run(env, SYSTEM, "verify")

    # A legacy active system must not ignore a stray helpers/current pointer.
    atomic_pointer(data / "system/current", baseline)
    assert "schema 1 cannot silently own" in run(env, SYSTEM, "verify", ok=False)

print("PASS: schema2 helper digests, pointer readback and safe cross-schema rollback gate")
