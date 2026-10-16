#!/usr/bin/env python3
"""Deterministic contract tests for coordinated generation collection."""
from __future__ import annotations

import fcntl
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "core"))
import generation_gc
import system


def make_layout(root: Path, count: int = 9) -> tuple[Path, Path, Path, list[str]]:
    data = root / "data"
    runtime = root / "runtime"
    shell_root = data / "builds"
    dots_root = data / "dotfiles/builds"
    system_root = data / "system/builds"
    for path in (shell_root, dots_root, system_root, runtime):
        path.mkdir(parents=True)
    names = [f"20260918-{index:06d}" for index in range(count)]
    for name in names:
        shell = shell_root / name
        shell.mkdir()
        (shell / "shell.qml").write_text("// test\n", encoding="utf-8")
        (shell / "BUILD_ID").write_text(name + "\n", encoding="utf-8")
        (shell / "BUILD.json").write_text(json.dumps({"schema": 1, "buildId": name}) + "\n", encoding="utf-8")
        dots = dots_root / name
        (dots / "home").mkdir(parents=True)
        (dots / "MANIFEST.json").write_text(json.dumps({"schema": 1, "buildId": name, "entries": []}) + "\n", encoding="utf-8")
    for index, name in enumerate(names):
        system = system_root / name
        system.mkdir()
        (system / "SYSTEM.json").write_text(json.dumps({
            "schema": 1,
            "buildId": name,
            "shellGeneration": str(shell_root / name),
            "dotfilesGeneration": str(dots_root / name),
        }) + "\n", encoding="utf-8")
    (runtime / "current").symlink_to(shell_root / names[-1])
    (runtime / "previous").symlink_to(shell_root / names[-2])
    (data / "dotfiles/current").symlink_to(dots_root / names[-1])
    (data / "dotfiles/previous").symlink_to(dots_root / names[-2])
    (data / "system/current").symlink_to(system_root / names[-1])
    (data / "system/previous").symlink_to(system_root / names[-2])
    return data, runtime, system_root, names


def env_for(data: Path, runtime: Path) -> dict[str, str]:
    env = os.environ.copy()
    env.update(CORTETSU_DATA_ROOT=str(data), CORTETSU_RUNTIME_ROOT=str(runtime))
    return env


def names_in(path: Path) -> set[str]:
    return {child.name for child in path.iterdir()}


def expect_error(fragment: str, call, *args, **kwargs) -> None:
    try:
        call(*args, **kwargs)
    except generation_gc.GenerationGCError as exc:
        assert fragment in str(exc), (fragment, str(exc))
    else:
        raise AssertionError(f"expected GenerationGCError containing {fragment!r}")


def simulate_install(data: Path, runtime: Path, name: str) -> None:
    """Build a new shell + dotfiles generation, move their links, promote."""
    shell = data / "builds" / name
    shell.mkdir()
    (shell / "shell.qml").write_text("// test\n", encoding="utf-8")
    (shell / "BUILD_ID").write_text(name + "\n", encoding="utf-8")
    (shell / "BUILD.json").write_text(json.dumps({"schema": 1, "buildId": name}) + "\n", encoding="utf-8")
    dots = data / "dotfiles/builds" / name
    (dots / "home").mkdir(parents=True)
    (dots / "MANIFEST.json").write_text(json.dumps({"schema": 1, "buildId": name, "entries": []}) + "\n", encoding="utf-8")
    for current, previous, target in (
        (runtime / "current", runtime / "previous", shell),
        (data / "dotfiles/current", data / "dotfiles/previous", dots),
    ):
        system.atomic_link(current.resolve(strict=True), previous)
        system.atomic_link(target, current)
    system.build_id = lambda: f"30000101-{name}"  # unique, sorts newest
    assert system.promote(ROOT) == 0


def cli(env: dict[str, str], *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [sys.executable, str(ROOT / "core/generation_gc.py"), "--repo", str(ROOT), *args],
        env=env, text=True, capture_output=True, check=False,
    )


# 1. Read-only planning, retention categories and pins.
with tempfile.TemporaryDirectory(prefix="cortetsu-gc-test-") as temporary:
    root = Path(temporary)
    data, runtime, system_root, names = make_layout(root)
    os.environ.update(env_for(data, runtime))
    plan = generation_gc.build_plan(keep=2)
    before = names_in(data / "builds")
    assert len(plan.layers["system"].protected) == 4  # current, previous, latest two additional
    assert plan.layers["system"].reasons[system_root / names[-1]] == ("current",)
    assert plan.layers["system"].reasons[system_root / names[-3]] == ("additional",)
    assert "referenced" in plan.layers["shell"].reasons[data / "builds" / names[-3]]
    assert names[0] in {path.name for path in plan.layers["shell"].deletions}
    assert names_in(data / "builds") == before

    (data / "pins").mkdir()
    for layer in ("shell", "dotfiles", "system"):
        (data / f"pins/{layer}.txt").write_text(names[0] + "\n", encoding="utf-8")
    pinned = generation_gc.build_plan(keep=0)
    assert pinned.layers["shell"].reasons[data / "builds" / names[0]] == ("referenced", "pinned")
    assert system_root / names[0] in pinned.layers["system"].protected
    report = generation_gc.render(pinned, True)
    assert f"DELETE {names[1]}" in report and f"KEEP   {names[0]} [referenced,pinned]" in report
    assert f"PLAN_ID {pinned.plan_id}" in report and "TOTAL_RECLAIM=" in report
    for layer in ("shell", "dotfiles", "system"):
        (data / f"pins/{layer}.txt").write_text("\n", encoding="utf-8")

    # The default CLI, the old installer invocation and a bare --keep never delete.
    env = env_for(data, runtime)
    for args in ((), ("--keep", "0"), ("--dry-run", "--keep", "0")):
        result = cli(env, *args)
        assert result.returncode == 0, result.stderr
        assert "DELETE" in result.stdout and "Nada se borró" in result.stdout
    assert names_in(data / "builds") == before
    result = cli(env, "--apply", "--keep", "0")
    assert result.returncode == 1 and "--plan-id" in result.stderr
    assert names_in(data / "builds") == before

    # Apply exactly the reviewed plan; a second apply needs a new plan id.
    approved = generation_gc.build_plan(keep=0)
    expected_gone = {path.name for path in approved.layers["shell"].deletions}
    generation_gc.run(ROOT, keep=0, dry_run=False, plan_id=approved.plan_id)
    assert names_in(data / "builds") == before - expected_gone
    assert generation_gc.build_plan(keep=0).plan_id != approved.plan_id
    expect_error("el plan cambió", generation_gc.run, ROOT, keep=0, dry_run=False, plan_id=approved.plan_id)
    assert (runtime / "current").resolve(strict=True).name == names[-1]
    assert (runtime / "previous").resolve(strict=True).name == names[-2]
    assert system.rollback(ROOT) == 0  # rollback still works after collection
    assert (runtime / "current").resolve(strict=True).name == names[-2]


# 2. The original defect: zero planned deletions before install, non-zero after.
with tempfile.TemporaryDirectory(prefix="cortetsu-gc-install-") as temporary:
    root = Path(temporary)
    data, runtime, system_root, names = make_layout(root, count=7)  # current+previous+5
    os.environ.update(env_for(data, runtime))
    preflight = generation_gc.build_plan(keep=5)
    assert sum(len(layer.deletions) for layer in preflight.layers.values()) == 0
    original = names_in(data / "builds")
    for index in range(3):  # several consecutive installs
        simulate_install(data, runtime, f"20260919-{index:06d}")
        # What the installer now runs after promotion: inspection only.
        assert cli(env_for(data, runtime), "--keep", "5").returncode == 0
    assert original <= names_in(data / "builds"), "install must not delete old generations"
    after = generation_gc.build_plan(keep=5)
    assert {path.name for path in after.layers["shell"].deletions} == set(sorted(original)[:3])
    expect_error("el plan cambió", generation_gc.run, ROOT, keep=5, dry_run=False, plan_id=preflight.plan_id)
    assert original <= names_in(data / "builds")
    assert system.rollback(ROOT) == 0
    assert (runtime / "current").resolve(strict=True).name == "20260919-000001"


# 3. Concurrency, archives, space and unsafe references.
with tempfile.TemporaryDirectory(prefix="cortetsu-gc-safety-") as temporary:
    root = Path(temporary)
    data, runtime, system_root, names = make_layout(root)
    os.environ.update(env_for(data, runtime))
    plan = generation_gc.build_plan(keep=0)
    before = names_in(data / "builds")

    for lock_name in ("install.lock", "build.lock", "system/system.lock", "gc.lock"):
        with (data / lock_name).open("a") as held:
            fcntl.flock(held, fcntl.LOCK_EX)
            expect_error("en curso", generation_gc.run, ROOT, keep=0, dry_run=False, plan_id=plan.plan_id)
    assert names_in(data / "builds") == before

    real_usage = generation_gc.shutil.disk_usage
    generation_gc.shutil.disk_usage = lambda _path: real_usage(data)._replace(free=1024)
    try:
        expect_error("espacio insuficiente", generation_gc.run, ROOT, keep=0, dry_run=False, plan_id=plan.plan_id, archive=True)
    finally:
        generation_gc.shutil.disk_usage = real_usage
    assert names_in(data / "builds") == before
    assert not (data / "gc-backups").exists(), "a refused archive must not leave a partial backup"

    deleted = plan.layers["shell"].deletions
    generation_gc.run(ROOT, keep=0, dry_run=False, plan_id=plan.plan_id, archive=True)
    backups = list((data / "gc-backups").iterdir())
    assert len(backups) == 1
    for path in deleted:
        archive = backups[0] / "archives/shell" / f"{path.name}.tar.gz"
        with generation_gc.tarfile.open(archive) as handle:
            assert f"{path.name}/BUILD.json" in handle.getnames()
        assert not path.exists()

    current_meta = system_root / names[-1] / "SYSTEM.json"
    original_meta = current_meta.read_text(encoding="utf-8")
    current_meta.write_text("{broken\n", encoding="utf-8")
    expect_error("SYSTEM.json", generation_gc.build_plan)
    current_meta.write_text(original_meta, encoding="utf-8")
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(root / "outside")
    expect_error("inexistente", generation_gc.build_plan)
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(data / "builds" / names[-2])
    expect_error("drift", generation_gc.build_plan)
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(data / "builds" / names[-1])
    (data / "pins").mkdir(exist_ok=True)
    (data / "pins/shell.txt").write_text("../escape\n", encoding="utf-8")
    expect_error("pin inválido", generation_gc.build_plan)

print("PASS: GC is inspection-only by default; deletion needs a fresh approved plan id, holds every generation lock, archives verifiably and keeps rollback")
