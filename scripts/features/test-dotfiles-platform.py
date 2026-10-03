#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CORE = REPO / "core/dotfiles.py"
DOCTOR = REPO / "core/doctor.py"


def run(env: dict[str, str], *args: str) -> str:
    proc = subprocess.run(
        ["python3", str(CORE), *args, "--repo", str(REPO), "--profile", "personal"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    return proc.stdout


with tempfile.TemporaryDirectory(prefix="cortetsu-dotfiles-test-") as tmp:
    root = Path(tmp)
    home = root / "home"
    data = home / ".local/share/cortetsu"
    home.mkdir(parents=True)
    env = os.environ.copy()
    env["HOME"] = str(home)
    env["CORTETSU_DATA_ROOT"] = str(data)
    env["XDG_CONFIG_HOME"] = str(home / ".config")

    unmanaged = home / ".config/cortetsu/ui.toml"
    unmanaged.parent.mkdir(parents=True)
    unmanaged.write_text("legacy=true\n", encoding="utf-8")

    plan = run(env, "plan")
    assert "backup+adopt" in plan
    assert ".config/cortetsu/ui.toml" in plan

    first = run(env, "apply")
    assert "PROMOTED dotfiles=" in first
    run(env, "verify")

    current_link = data / "dotfiles/current"
    first_generation = current_link.resolve(strict=True)
    assert (first_generation / "MANIFEST.json").is_file()
    payload = json.loads((first_generation / "MANIFEST.json").read_text(encoding="utf-8"))
    assert payload["schema"] == 1
    assert payload["profile"] == "personal"
    assert len(payload["entries"]) >= 6

    target = home / ".config/cortetsu/ui.toml"
    assert target.is_symlink()
    assert target.read_text(encoding="utf-8").startswith("schema = 1")
    service = home / ".config/systemd/user/cortetsu-shell.service"
    assert service.is_symlink()
    hypr_loader = home / ".config/hypr/hyprland.lua"
    assert hypr_loader.is_file() and not hypr_loader.is_symlink()
    assert "dotfiles/current/home/.config/hypr/hyprland.lua" in hypr_loader.read_text(encoding="utf-8")

    backups = list((data / "dotfiles/backups").glob("*/home/.config/cortetsu/ui.toml"))
    assert backups, "unmanaged config was not backed up"
    assert backups[-1].read_text(encoding="utf-8") == "legacy=true\n"

    # Machine-readable doctor output must remain valid JSON even when a required
    # runtime check is expected to fail in the isolated test HOME.
    doctor = subprocess.run(
        ["python3", str(DOCTOR), "--repo", str(REPO), "--profile", "personal", "--json"],
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    doctor_payload = json.loads(doctor.stdout)
    assert doctor_payload["schema"] == 1
    assert any(item["name"] == "dotfiles" and item["status"] == "ok" for item in doctor_payload["checks"])
    assert any(item["name"] == "runtime" and item["status"] == "error" for item in doctor_payload["checks"])

    second = run(env, "apply")
    assert "PREVIOUS dotfiles=" in second
    second_generation = current_link.resolve(strict=True)
    assert second_generation != first_generation
    previous_link = data / "dotfiles/previous"
    assert previous_link.resolve(strict=True) == first_generation
    run(env, "verify")

    rolled = run(env, "rollback")
    assert "ROLLED BACK dotfiles" in rolled
    assert current_link.resolve(strict=True) == first_generation
    assert previous_link.resolve(strict=True) == second_generation
    run(env, "verify")

    gc = run(env, "gc", "--keep", "1")
    assert "GC removed=" in gc
    assert current_link.resolve(strict=True).exists()
    assert previous_link.resolve(strict=True).exists()

print("PASS: immutable dotfiles plan/apply/backup/doctor/verify/rollback/gc contract")
