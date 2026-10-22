#!/usr/bin/env python3
"""Safely reconcile legacy process launchers without signaling processes."""
from __future__ import annotations

import argparse
import fcntl
import os
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

LEGACY = {
    "pomodoro": ("caerice-pomodoro", "cortetsu-pomodoro"),
    "wallpaper-color": ("caelestia-wallpaper-color-daemon", None),
}
TEXT_SUFFIXES = {".lua", ".fish", ".service", ".desktop", ".conf", ".sh", ".toml"}


def roots(home: Path) -> list[Path]:
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    return [config / "hypr", config / "quickshell", config / "systemd/user"]


def files_to_scan(home: Path) -> list[Path]:
    result: list[Path] = []
    for root in roots(home):
        if root.is_dir():
            result.extend(path for path in root.rglob("*") if path.is_file() and path.suffix in TEXT_SUFFIXES)
    return sorted(set(result))


def classify(text: str) -> set[str]:
    return {name for name, (legacy, _) in LEGACY.items() if legacy in text}


def live_processes() -> list[tuple[str, str]]:
    result: list[tuple[str, str]] = []
    for entry in Path("/proc").glob("[0-9]*"):
        try:
            command = (entry / "cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()
        except OSError:
            continue
        for name, (legacy, _) in LEGACY.items():
            if legacy in command:
                result.append((name, f"pid={entry.name} cmd={command}"))
    return result


def backup_path(path: Path, home: Path, backup: Path) -> Path:
    config = Path(os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    relative = path.relative_to(config)
    target = backup / "config" / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, target)
    return target


def report(home: Path) -> str:
    found: dict[str, list[str]] = {name: [] for name in LEGACY}
    for path in files_to_scan(home):
        for name in classify(path.read_text(encoding="utf-8", errors="replace")):
            found[name].append(str(path))
    lines = ["Legacy process audit", "===================="]
    for name, paths in found.items():
        status = "FOUND" if paths else "ABSENT"
        lines.append(f"{name}: {status}")
        lines.extend(f"  {path}" for path in paths)
        if name == "wallpaper-color" and paths:
            lines.append("  action: DEFERRED (no Cortetsu replacement; no process signal sent)")
    processes = live_processes()
    lines.append("live processes: " + ("none" if not processes else "FOUND"))
    lines.extend(f"  {name}: {details}" for name, details in processes)
    if processes:
        lines.append("  action: audit-only; ownership must be resolved before any stop")
    return "\n".join(lines)


def migrate(home: Path, data_root: Path) -> int:
    lock_path = data_root / "legacy-processes.lock"
    data_root.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
        backup = data_root / "migrations" / stamp / "legacy-processes"
        changed = 0
        deferred = 0
        for path in files_to_scan(home):
            original = path.read_text(encoding="utf-8", errors="replace")
            kinds = classify(original)
            if "wallpaper-color" in kinds and not (home / ".local/bin/cortetsu-wallpaper-color-daemon").exists():
                deferred += 1
            if not kinds or ("pomodoro" not in kinds and "wallpaper-color" not in kinds):
                continue
            if "pomodoro" in kinds and not (home / ".local/bin/cortetsu-pomodoro").exists():
                print("DEFERRED pomodoro: Cortetsu helper is not installed", file=sys.stderr)
            if "wallpaper-color" in kinds and not (home / ".local/bin/cortetsu-wallpaper-color-daemon").exists():
                continue
            if path.is_symlink():
                print(f"DEFERRED managed symlink: update its Cortetsu source instead: {path}")
                continue
            backup_path(path, home, backup)
            updated = original.replace("caerice-pomodoro", "cortetsu-pomodoro")
            updated = updated.replace("caelestia-wallpaper-color-daemon", "cortetsu-wallpaper-color-daemon")
            if updated != original:
                path.write_text(updated, encoding="utf-8")
                changed += 1
        marker = data_root / "legacy-processes.last"
        marker.write_text(f"changed={changed}\ndeferred={deferred}\nbackup={backup}\n", encoding="utf-8")
        print(f"MIGRATED pomodoro_files={changed} deferred_wallpaper_files={deferred}")
        print(f"BACKUP legacy-processes={backup}")
        print("NO_PROCESS_SIGNALING")
        return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=("scan", "migrate"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--data-root", type=Path, default=None)
    args = parser.parse_args()
    if args.command == "scan":
        print(report(args.home))
        return 0
    data_root = args.data_root or Path(os.environ.get("CORTETSU_DATA_ROOT", Path.home() / ".local/share/cortetsu"))
    return migrate(args.home, data_root)


if __name__ == "__main__":
    raise SystemExit(main())
