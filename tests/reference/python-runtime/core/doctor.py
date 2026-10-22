#!/usr/bin/env python3
from __future__ import annotations

import argparse
import contextlib
import io
import json
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dotfiles
import shell_lifecycle

def check(name: str, status: str, detail: str, required: bool = False) -> dict:
    return {"name": name, "status": status, "detail": detail, "required": required}


def package_installed(package: str) -> bool | None:
    if shutil.which("pacman") is None:
        return None
    return subprocess.run(["pacman", "-Q", package], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode == 0


def theme_ownership_check(home: Path) -> dict:
    del home
    source = Path(__file__).resolve().parents[1] / "dotfiles/home/.config/cortetsu/ui.toml"
    if not source.is_file():
        return check("theme-ownership", "error", f"Cortetsu theme source missing: {source}", True)
    try:
        import tomllib
        with source.open("rb") as handle:
            payload = tomllib.load(handle)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        return check("theme-ownership", "error", f"cannot read {source}: {exc}", True)
    if payload.get("schema") != 1 or not isinstance(payload.get("palette"), dict):
        return check("theme-ownership", "error", "Cortetsu ui.toml has an invalid schema", True)
    return check("theme-ownership", "ok", "Cortetsu owns terminal/Hyprland/GTK/Qt theme surfaces", True)


def run(repo: Path, profile_name: str | None) -> list[dict]:
    results: list[dict] = []
    _, profile, _ = dotfiles.load_manifest(repo, profile_name)
    package_manifest = repo / "packages/arch.toml"
    with package_manifest.open("rb") as handle:
        packages = tomllib.load(handle)

    groups = packages.get("group", {})
    for group_name in profile["package_groups"]:
        group = groups.get(group_name)
        if not isinstance(group, dict):
            results.append(check(f"package-group:{group_name}", "error", "grupo inexistente", True))
            continue
        required = bool(group.get("required", False))
        for command in group.get("commands", []):
            found = shutil.which(str(command))
            results.append(check(f"cmd:{command}", "ok" if found else ("error" if required else "warn"), found or "missing", required))
        for package in group.get("packages", []):
            installed = package_installed(str(package))
            if installed is None:
                continue
            results.append(check(f"pkg:{package}", "ok" if installed else ("error" if required else "warn"), "installed" if installed else "missing", required))

    runtime = Path.home() / ".config/quickshell/cortetsu/current/shell.qml"
    results.append(check("runtime", "ok" if runtime.is_file() else "error", str(runtime), True))

    try:
        # verify() is intentionally user-friendly and prints a PASS line. Doctor
        # captures it so --json always remains machine-parseable.
        with contextlib.redirect_stdout(io.StringIO()):
            dotfiles.verify(repo, profile_name)
    except Exception as exc:
        results.append(check("dotfiles", "error", str(exc), True))
    else:
        results.append(check("dotfiles", "ok", "immutable generation verified", True))

    if shutil.which("systemctl"):
        rc = subprocess.run(["systemctl", "--user", "show-environment"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode
        results.append(check("systemd-user", "ok" if rc == 0 else "warn", "available" if rc == 0 else "user manager unavailable"))
        enabled = subprocess.run(["systemctl", "--user", "is-enabled", "cortetsu-shell.service"], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
        state = enabled.stdout.strip() or "disabled/unavailable"
        results.append(check("shell-supervision", "ok" if enabled.returncode == 0 else "warn", state))

    service = Path.home() / ".config/systemd/user/cortetsu-shell.service"
    results.append(check("shell-service", "ok" if service.exists() else "warn", str(service)))

    legacy_lifecycle = shell_lifecycle.scan(Path.home())
    if legacy_lifecycle:
        detail = "; ".join(str(item["path"]) for item in legacy_lifecycle)
        results.append(check("shell-lifecycle", "error", f"legacy direct launch/kill references: {detail}", True))
    else:
        results.append(check("shell-lifecycle", "ok", "systemd --user is the only process owner", True))

    results.append(theme_ownership_check(Path.home()))

    secret_tool = shutil.which("secret-tool")
    results.append(check("secret-service", "ok" if secret_tool else "warn", secret_tool or "secret-tool missing"))

    try:
        dirty = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True).strip()
        results.append(check("git-worktree", "warn" if dirty else "ok", "dirty" if dirty else "clean"))
    except (OSError, subprocess.CalledProcessError):
        pass
    return results


def main() -> int:
    parser = argparse.ArgumentParser(description="Cortetsu system doctor")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--profile")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    results = run(args.repo.resolve(), args.profile)
    if args.json:
        print(json.dumps({"schema": 1, "checks": results}, indent=2))
    else:
        print("Cortetsu doctor")
        for item in results:
            mark = {"ok": "PASS", "warn": "WARN", "error": "FAIL"}[item["status"]]
            print(f"{mark:4} {item['name']}: {item['detail']}")
    return 1 if any(item["status"] == "error" and item["required"] for item in results) else 0


if __name__ == "__main__":
    raise SystemExit(main())
