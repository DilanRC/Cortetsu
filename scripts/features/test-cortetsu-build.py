#!/usr/bin/env python3
"""E2E gate: unmanaged runtime -> two unified Cortetsu systems -> rollback."""
from __future__ import annotations

import subprocess
import tempfile
import os
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="cortetsu-e2e-") as temporary:
    root = Path(temporary)
    home = root / "home"
    data = root / "data"
    runtime = root / "runtime"
    unmanaged = root / "unmanaged-runtime"
    home.mkdir()
    runtime.mkdir()
    unmanaged.mkdir()
    (unmanaged / "shell.qml").write_text("// pre-v2 runtime without BUILD.json\n", encoding="utf-8")
    (runtime / "current").symlink_to(unmanaged, target_is_directory=True)

    env = {
        **os.environ,
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(home / ".config"),
        "CORTETSU_DATA_ROOT": str(data),
        "CORTETSU_RUNTIME_ROOT": str(runtime),
        "CORTETSU_REPOSITORY": str(repo),
    }

    build = repo / "cortetsu/bin/build-runtime.sh"
    dotfiles = repo / "core/dotfiles.py"
    system = repo / "core/system.py"
    cli = repo / "scripts/cortetsu"

    subprocess.run([str(build)], cwd=repo, env=env, check=True)
    shell1 = (runtime / "current").resolve()
    assert shell1 != unmanaged
    assert (shell1 / "shell.qml").is_file()
    assert (shell1 / "modules/calendar/Content.qml").is_file()
    assert (shell1 / "BUILD.json").is_file()
    assert not (runtime / "previous").exists()
    assert (runtime / "legacy-previous").resolve() == unmanaged

    # A promoted generation must retain the selected scheme instead of
    # reverting to the source-generated design defaults.
    scheme = repo / "cortetsu/bin/cortetsu-scheme"
    scheme_env = {**env, "CORTETSU_REPOSITORY": str(repo)}
    subprocess.run(
        [str(scheme), "set", "-n", "aura", "default"],
        cwd=repo,
        env={**scheme_env, "CORTETSU_SKIP_RELOAD": "1"},
        check=True,
    )
    aura_primary = next(
        line.split(None, 1)[1].strip().upper()
        for line in (repo / "cortetsu/data/schemes/cortetsu-pack/aura/default/dark.txt").read_text().splitlines()
        if line.startswith("primary ")
    )

    subprocess.run(
        ["python3", str(dotfiles), "apply", "--repo", str(repo), "--profile", "personal"],
        cwd=repo,
        env=env,
        check=True,
    )
    dots1 = (data / "dotfiles/current").resolve(strict=True)
    subprocess.run(["python3", str(system), "promote", "--repo", str(repo)], cwd=repo, env=env, check=True)
    system1 = (data / "system/current").resolve(strict=True)

    # Reproduce an upgrade edge case: shell current is managed while shell
    # previous still points at the unmanaged pre-v2 generation.
    (runtime / "previous").symlink_to(unmanaged, target_is_directory=True)
    subprocess.run([str(cli), "verify"], cwd=repo, env=env, check=True)

    subprocess.run([str(build)], cwd=repo, env=env, check=True)
    shell2 = (runtime / "current").resolve()
    assert shell2 != shell1
    assert (runtime / "previous").resolve() == shell1
    assert (runtime / "legacy-previous").resolve() == unmanaged
    assert f'var colorPrimary = "#{aura_primary}"' in (
        shell2 / "modules/CortetsuDesign.js"
    ).read_text(encoding="utf-8")

    subprocess.run(
        ["python3", str(dotfiles), "apply", "--repo", str(repo), "--profile", "personal"],
        cwd=repo,
        env=env,
        check=True,
    )
    dots2 = (data / "dotfiles/current").resolve(strict=True)
    assert dots2 != dots1
    subprocess.run(["python3", str(system), "promote", "--repo", str(repo)], cwd=repo, env=env, check=True)
    system2 = (data / "system/current").resolve(strict=True)
    assert system2 != system1
    assert (data / "system/previous").resolve(strict=True) == system1
    subprocess.run([str(cli), "verify"], cwd=repo, env=env, check=True)

    # Top-level rollback is the product contract: shell and dotfiles move
    # together to the exact previous Cortetsu system generation.
    subprocess.run([str(cli), "rollback"], cwd=repo, env=env, check=True)
    assert (data / "system/current").resolve(strict=True) == system1
    assert (data / "system/previous").resolve(strict=True) == system2
    assert (runtime / "current").resolve(strict=True) == shell1
    assert (runtime / "previous").resolve(strict=True) == shell2
    assert (data / "dotfiles/current").resolve(strict=True) == dots1
    assert (data / "dotfiles/previous").resolve(strict=True) == dots2
    assert (runtime / "legacy-previous").resolve() == unmanaged
    subprocess.run([str(cli), "verify"], cwd=repo, env=env, check=True)

print("PASS: shell + dotfiles promote and roll back as one Cortetsu system")
