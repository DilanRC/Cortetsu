#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import sys
from datetime import datetime, timezone
from pathlib import Path

LEGACY_REPLACEMENTS = (
    (
        "qs -c caelestia kill; sleep .1; caelestia shell -d",
        "systemctl --user restart cortetsu-shell.service",
    ),
    (
        "qs -c caelestia kill",
        "systemctl --user stop cortetsu-shell.service",
    ),
    (
        "caelestia shell -d",
        "systemctl --user start cortetsu-shell.service",
    ),
    (
        "caelestia screenshot",
        "cortetsu screenshot",
    ),
    (
        "caelestia emoji",
        "cortetsu emoji",
    ),
)

ACTIVE_RELATIVE_FILES = (
    Path(".config/hypr/hyprland/execs.lua"),
    Path(".config/hypr/hyprland/keybinds.lua"),
)


def data_root(home: Path) -> Path:
    override = os.environ.get("CORTETSU_DATA_ROOT")
    if override:
        return Path(override).expanduser()
    xdg = os.environ.get("XDG_DATA_HOME")
    return Path(xdg).expanduser() / "cortetsu" if xdg else home / ".local/share/cortetsu"


def active_files(home: Path) -> list[Path]:
    return [home / relative for relative in ACTIVE_RELATIVE_FILES]


def occurrences(path: Path) -> list[str]:
    if not path.is_file():
        return []
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return []
    found: list[str] = []
    for legacy, _replacement in LEGACY_REPLACEMENTS:
        if legacy in text:
            found.append(legacy)
    return found


def scan(home: Path) -> list[dict[str, object]]:
    results: list[dict[str, object]] = []
    for path in active_files(home):
        matches = occurrences(path)
        if matches:
            results.append({"path": str(path), "matches": matches})
    return results


def atomic_write(path: Path, text: str, mode: int) -> None:
    temporary = path.with_name(f".{path.name}.cortetsu-tmp-{os.getpid()}")
    try:
        temporary.write_text(text, encoding="utf-8")
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def backup_file(path: Path, home: Path, backup_root: Path) -> Path:
    try:
        relative = path.relative_to(home)
    except ValueError as exc:
        raise RuntimeError(f"ruta fuera de HOME: {path}") from exc
    destination = backup_root / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, destination)
    return destination


def migrate(home: Path) -> tuple[list[Path], Path | None]:
    home = home.expanduser().resolve()
    candidates = [(path, occurrences(path)) for path in active_files(home)]
    candidates = [(path, matches) for path, matches in candidates if matches]
    if not candidates:
        return [], None

    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_root = data_root(home) / "migrations" / stamp / "hypr-shell-lifecycle"
    changed: list[Path] = []

    for path, _matches in candidates:
        original = path.read_text(encoding="utf-8")
        updated = original
        for legacy, replacement in LEGACY_REPLACEMENTS:
            updated = updated.replace(legacy, replacement)
        if updated == original:
            continue
        backup_file(path, home, backup_root)
        mode = stat.S_IMODE(path.stat().st_mode)
        atomic_write(path, updated, mode)
        changed.append(path)

    remaining = scan(home)
    if remaining:
        rendered = ", ".join(item["path"] for item in remaining)
        raise RuntimeError(f"quedaron referencias legacy de lifecycle: {rendered}")
    return changed, backup_root if changed else None


def main() -> int:
    parser = argparse.ArgumentParser(description="Cortetsu Hyprland shell lifecycle migration")
    parser.add_argument("action", choices=("scan", "migrate", "verify"))
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    home = args.home.expanduser().resolve()

    try:
        if args.action == "scan":
            result = scan(home)
            if args.json:
                print(json.dumps({"schema": 1, "legacyLifecycle": result}, indent=2))
            elif not result:
                print("PASS: Hyprland shell lifecycle is systemd-owned")
            else:
                print("Legacy shell lifecycle references:")
                for item in result:
                    print(f"  {item['path']}")
                    for match in item["matches"]:
                        print(f"    - {match}")
            return 1 if result else 0

        if args.action == "verify":
            result = scan(home)
            if result:
                for item in result:
                    print(f"ERROR: lifecycle legacy en {item['path']}", file=sys.stderr)
                return 1
            print("PASS: Hyprland shell lifecycle is systemd-owned")
            return 0

        changed, backup = migrate(home)
        if not changed:
            print("Cortetsu shell lifecycle: already reconciled")
            return 0
        for path in changed:
            print(f"MIGRATED lifecycle={path}")
        print(f"BACKUP lifecycle={backup}")
        print("Cortetsu shell lifecycle: systemd --user is the only process owner")
        return 0
    except (OSError, RuntimeError, UnicodeDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
