#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
DOTFILES = REPO / "core/dotfiles.py"
SYSTEM = REPO / "core/system.py"


def run(env: dict[str, str], script: Path, *args: str) -> str:
    proc = subprocess.run(
        ["python3", str(script), *args, "--repo", str(REPO)],
        env=env,
        cwd=REPO,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    return proc.stdout


def shell_generation(path: Path, build_id: str) -> None:
    path.mkdir(parents=True)
    (path / "shell.qml").write_text("// test shell\n", encoding="utf-8")
    (path / "BUILD_ID").write_text(build_id + "\n", encoding="utf-8")
    (path / "BUILD.json").write_text(
        json.dumps({
            "schema": 1,
            "sourceProject": "Cortetsu",
            "buildId": build_id,
            "repositoryRevision": "test",
        }) + "\n",
        encoding="utf-8",
    )


with tempfile.TemporaryDirectory(prefix="cortetsu-system-test-") as tmp:
    root = Path(tmp)
    home = root / "home"
    data = root / "data"
    runtime = root / "runtime"
    shell_builds = root / "shell-builds"
    home.mkdir()
    runtime.mkdir()
    shell_builds.mkdir()

    env = os.environ.copy()
    env.update(
        HOME=str(home),
        XDG_CONFIG_HOME=str(home / ".config"),
        CORTETSU_DATA_ROOT=str(data),
        CORTETSU_RUNTIME_ROOT=str(runtime),
    )

    shell1 = shell_builds / "shell-1"
    shell2 = shell_builds / "shell-2"
    shell_generation(shell1, "shell-1")
    shell_generation(shell2, "shell-2")

    (runtime / "current").symlink_to(shell1, target_is_directory=True)
    run(env, DOTFILES, "apply", "--profile", "personal")
    dots1 = (data / "dotfiles/current").resolve(strict=True)
    first_promote = run(env, SYSTEM, "promote")
    assert "PROMOTED system=" in first_promote
    system1 = (data / "system/current").resolve(strict=True)
    run(env, SYSTEM, "verify")

    (runtime / "previous").symlink_to(shell1, target_is_directory=True)
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(shell2, target_is_directory=True)
    run(env, DOTFILES, "apply", "--profile", "personal")
    dots2 = (data / "dotfiles/current").resolve(strict=True)
    assert dots2 != dots1
    second_promote = run(env, SYSTEM, "promote")
    assert "PREVIOUS system=" in second_promote
    system2 = (data / "system/current").resolve(strict=True)
    assert system2 != system1
    assert (data / "system/previous").resolve(strict=True) == system1
    run(env, SYSTEM, "verify")

    rollback = run(env, SYSTEM, "rollback")
    assert "ROLLED BACK system" in rollback
    assert (data / "system/current").resolve(strict=True) == system1
    assert (data / "system/previous").resolve(strict=True) == system2
    assert (runtime / "current").resolve(strict=True) == shell1
    assert (runtime / "previous").resolve(strict=True) == shell2
    assert (data / "dotfiles/current").resolve(strict=True) == dots1
    assert (data / "dotfiles/previous").resolve(strict=True) == dots2
    run(env, SYSTEM, "verify")

    # The per-layer action must not delete: it cannot see cross-layer references.
    builds_before = set((data / "system/builds").iterdir())
    gc = run(env, SYSTEM, "gc", "--keep", "0")
    assert "sin borrados" in gc
    assert set((data / "system/builds").iterdir()) == builds_before

print("PASS: unified system promotion/verify/rollback/gc keeps shell and dotfiles coherent")
