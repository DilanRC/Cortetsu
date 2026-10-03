#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LIVE = Path(os.environ.get("CORTETSU_LIVE_ROOT", str(Path.home() / ".config/quickshell/cortetsu/current")))
HOME = Path.home()
RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))


def run(*args: str, timeout: int = 12) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError) as exc:
        return subprocess.CompletedProcess(args, 127, "", str(exc))


def sha(path: Path) -> str:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return "MISSING"


def print_json_command(label: str, path: Path, *extra: str) -> None:
    print(f"\n===== {label} =====")
    cp = run(str(path), *extra)
    if cp.returncode != 0:
        print(f"ERROR exit={cp.returncode}: {(cp.stderr or cp.stdout).strip()}")
        return
    try:
        parsed = json.loads(cp.stdout)
        print(json.dumps(parsed, indent=2, ensure_ascii=False))
    except json.JSONDecodeError:
        print(cp.stdout.strip())


print("\n===== LIVE VS REPO =====")
repo_modules = REPO / "cortetsu/modules"
checks = [(repo_modules / "HardwareController.qml", LIVE / "modules/HardwareController.qml")]
for repo_path in sorted((repo_modules / "hardware").rglob("*.qml")):
    checks.append((repo_path, LIVE / "modules" / repo_path.relative_to(repo_modules)))
for repo_path, live_path in checks:
    repo_hash = sha(repo_path)
    live_hash = sha(live_path)
    state = "MATCH" if repo_hash == live_hash else "DIFF"
    print(f"{state:5} {live_path.relative_to(LIVE) if live_path.is_absolute() else live_path}")
    if state != "MATCH":
        print(f"      repo {repo_hash}")
        print(f"      live {live_hash}")

print_json_command("MAIN TELEMETRY", HOME / ".local/bin/cortetsu-hardware-probe")
print_json_command("POWER TELEMETRY", HOME / ".local/bin/cortetsu-hardware-power")
print_json_command("POWER AUTOMATION", HOME / ".local/bin/cortetsu-power-auto-control", "status")

print("\n===== IPC =====")
ipc = run("qs", "-p", str(LIVE), "ipc", "call", "hardware", "isOpen")
print(f"hardware isOpen: {(ipc.stdout or ipc.stderr).strip()}")

print("\n===== SYSTEMD AUTO SERVICE =====")
for verb in ("is-enabled", "is-active"):
    cp = run("systemctl", "--user", verb, "cortetsu-power-auto.service")
    value = (cp.stdout or cp.stderr).strip()
    print(f"{verb}: {value} (exit {cp.returncode})")

print("\n===== HARDWARE QML LOG ERRORS =====")
logs = list((RUNTIME / "quickshell/by-id").glob("*/log.qslog"))
if not logs:
    print("no quickshell log found")
else:
    latest = max(logs, key=lambda p: p.stat().st_mtime)
    data = latest.read_bytes().decode("utf-8", errors="ignore")
    patterns = re.compile(r".*(?:modules/hardware|HardwareController|Hardware Center).*(?:Error|ReferenceError|TypeError|Warning|unavailable|failed).*", re.I)
    lines = []
    for raw in data.splitlines():
        if patterns.search(raw):
            if "windowtitle" in raw.lower() or "activewindow" in raw.lower():
                continue
            lines.append(raw)
    print(f"log: {latest}")
    if lines:
        for line in lines[-40:]:
            print(line)
    else:
        print("none")

print("\nDIAGNÓSTICO TERMINADO")
