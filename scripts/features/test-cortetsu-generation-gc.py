#!/usr/bin/env python3
"""Deterministic contract tests for coordinated generation collection."""
from __future__ import annotations

import json
import os
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "core"))
import generation_gc


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


with tempfile.TemporaryDirectory(prefix="cortetsu-gc-test-") as temporary:
    root = Path(temporary)
    data, runtime, system_root, names = make_layout(root)
    os.environ.update(env_for(data, runtime))
    plan = generation_gc.build_plan(keep=2)
    before = sorted(path.name for path in (data / "builds").iterdir())
    assert len(plan.layers["system"].protected) == 4  # current, previous, latest two additional
    assert (data / "builds" / names[-1]) in plan.layers["shell"].protected
    assert (data / "builds" / names[-2]) in plan.layers["shell"].protected
    assert names[-3] in {path.name for path in plan.layers["shell"].protected}
    assert names[0] in {path.name for path in plan.layers["shell"].deletions}
    assert sorted(path.name for path in (data / "builds").iterdir()) == before

    (data / "pins").mkdir()
    (data / "pins/shell.txt").write_text(names[0] + "\n", encoding="utf-8")
    (data / "pins/dotfiles.txt").write_text(names[0] + "\n", encoding="utf-8")
    (data / "pins/system.txt").write_text(names[0] + "\n", encoding="utf-8")
    pinned = generation_gc.build_plan(keep=0)
    assert data / "builds" / names[0] in pinned.layers["shell"].protected
    assert data / "dotfiles/builds" / names[0] in pinned.layers["dotfiles"].protected
    assert system_root / names[0] in pinned.layers["system"].protected

    dry_run = generation_gc.render(pinned, True)
    assert "PROTECTED" in dry_run and "WOULD_DELETE" in dry_run and "estimated_reclaim" in dry_run
    generation_gc.run(ROOT, keep=0, dry_run=True)
    assert (data / "builds" / names[0]).exists()

    # A retained system build keeps both of its component generations alive.
    (data / "pins/system.txt").write_text("\n", encoding="utf-8")
    (data / "pins/shell.txt").write_text("\n", encoding="utf-8")
    (data / "pins/dotfiles.txt").write_text("\n", encoding="utf-8")
    no_extra = generation_gc.build_plan(keep=0)
    assert data / "builds" / names[-1] in no_extra.layers["shell"].protected
    assert data / "builds" / names[0] in no_extra.layers["shell"].deletions

    # Apply twice: the second plan has no deletions and preserves rollback links.
    generation_gc.run(ROOT, keep=0)
    remaining = {path.name for path in (data / "builds").iterdir()}
    generation_gc.run(ROOT, keep=0)
    assert remaining == {path.name for path in (data / "builds").iterdir()}
    assert (runtime / "current").resolve(strict=True).name == names[-1]
    assert (runtime / "previous").resolve(strict=True).name == names[-2]

    # Corrupt retained metadata, broken links, outside links, drift, and traversal all abort.
    current_meta = system_root / names[-1] / "SYSTEM.json"
    original_meta = current_meta.read_text(encoding="utf-8")
    current_meta.write_text("{broken\n", encoding="utf-8")
    try:
        generation_gc.build_plan()
        raise AssertionError("corrupt SYSTEM.json did not abort")
    except generation_gc.GenerationGCError:
        pass
    current_meta.write_text(original_meta, encoding="utf-8")
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(root / "outside")
    try:
        generation_gc.build_plan()
        raise AssertionError("outside symlink did not abort")
    except generation_gc.GenerationGCError:
        pass
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(data / "builds" / names[-2])
    try:
        generation_gc.build_plan()
        raise AssertionError("drift did not abort")
    except generation_gc.GenerationGCError:
        pass
    (runtime / "current").unlink()
    (runtime / "current").symlink_to(data / "builds" / names[-1])
    (data / "pins/shell.txt").write_text("../escape\n", encoding="utf-8")
    try:
        generation_gc.build_plan()
        raise AssertionError("path traversal pin did not abort")
    except generation_gc.GenerationGCError:
        pass

print("PASS: coordinated generation GC protects links, references, pins, rollback window and rejects unsafe plans")
