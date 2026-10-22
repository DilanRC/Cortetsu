#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

MAX_BYTES = 1024 * 1024
SKIP_DIRS = {".git", "backup", "backups", "cache", "logs", "legacy-backup"}
SKIP_SUFFIXES = (".bak", ".old", ".orig", ".tmp", ".swp", ".swo", "~")
# Cortetsu's own timestamped-backup convention (see CLAUDE.md fish snippets):
# `name.bak-20260905-131903` or `name.bak.20260905-131903`. A plain endswith
# check on SKIP_SUFFIXES misses these because the timestamp trails the token.
BACKUP_TOKEN = re.compile(r"\.(bak|old|orig|tmp|swp|swo)([.-]|$)", re.IGNORECASE)
SENSITIVE = re.compile(
    r"(?i)\b(password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret)\b\s*[:=]"
)

# The "modules" scope owns the dynamically-discovered ~/.config/hypr/hyprland/
# tree (per-domain Hyprland config split into files).
#
# The "core" scope owns the fixed set of files that make that tree loadable at
# all without ~/.config/caelestia as a Lua module root: the loader itself,
# shared variables, transitive utils, and the scheme fallback. These are not
# auto-discovered (unlike "modules") because the set is small, load-bearing,
# and enumerated explicitly by the Hyprland regression contract.
SCOPES = {
    "modules": {
        "begin": "# BEGIN CORTETSU HYPRLAND IMPORT",
        "end": "# END CORTETSU HYPRLAND IMPORT",
        "active_root": lambda home: home / ".config/hypr/hyprland",
        "imported_root": lambda repo: repo / "dotfiles/home/.config/hypr/hyprland",
        "source_prefix": "dotfiles/home/.config/hypr/hyprland",
        "target_prefix": ".config/hypr/hyprland",
        "discover": True,
        "files": (),
    },
    "core": {
        "begin": "# BEGIN CORTETSU HYPRLAND CORE IMPORT",
        "end": "# END CORTETSU HYPRLAND CORE IMPORT",
        "active_root": lambda home: home / ".config/hypr",
        "imported_root": lambda repo: repo / "dotfiles/home/.config/hypr",
        "source_prefix": "dotfiles/home/.config/hypr",
        "target_prefix": ".config/hypr",
        "discover": False,
        # The loader (hyprland.lua) plus every module it must resolve without
        # ~/.config/caelestia on package.path: variables, transitive utils,
        # and the scheme fallback. scheme/current.lua is deliberately excluded:
        # it is live, per-user theme state that hyprland.lua bootstraps from
        # scheme/default.lua on first run (see maybe_copy), not a fixed dotfile.
        "files": (
            "hyprland.lua",
            "variables.lua",
            "utils/functions.lua",
            "utils/json.lua",
            "scheme/default.lua",
            "verify.fish",
        ),
    },
}


class ImportError(RuntimeError):
    pass


@dataclass(frozen=True)
class Candidate:
    source: Path
    relative: Path
    size: int


def repo_root(value: str | None) -> Path:
    if value:
        return Path(value).expanduser().resolve()
    return Path(__file__).resolve().parents[1]


def is_backupish(path: Path) -> bool:
    lowered = path.name.lower()
    if any(part.lower() in SKIP_DIRS or part.lower().startswith("legacy-backup") for part in path.parts):
        return True
    return lowered.endswith(SKIP_SUFFIXES) or ".backup" in lowered or bool(BACKUP_TOKEN.search(lowered))


def inspect_file(path: Path) -> tuple[str, int]:
    try:
        size = path.stat().st_size
    except OSError as exc:
        return f"unreadable:{exc}", 0
    if size > MAX_BYTES:
        return "too-large", size
    try:
        raw = path.read_bytes()
    except OSError as exc:
        return f"unreadable:{exc}", size
    if b"\0" in raw:
        return "binary", size
    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError:
        return "non-utf8", size
    if SENSITIVE.search(text):
        return "sensitive", size
    return "ok", size


def scan(home: Path, scope: dict) -> tuple[list[Candidate], list[tuple[Path, str]]]:
    root = scope["active_root"](home)
    if not root.is_dir():
        raise ImportError(f"árbol Hyprland activo inexistente: {root}")
    accepted: list[Candidate] = []
    rejected: list[tuple[Path, str]] = []

    if scope["discover"]:
        paths = sorted(root.rglob("*"), key=lambda item: item.as_posix())
    else:
        paths = [root / name for name in scope["files"]]

    for path in paths:
        rel = path.relative_to(root) if path.is_absolute() else path
        if not scope["discover"] and not path.exists():
            # Fixed-file scope: an absent file is a plan-time omission, not a
            # rejection. The runtime loader is what enforces "required".
            continue
        if is_backupish(rel):
            if path.is_file() or path.is_symlink():
                rejected.append((rel, "backup/temp"))
            continue
        if path.is_dir():
            continue
        if path.is_symlink():
            rejected.append((rel, "symlink"))
            continue
        if not path.is_file():
            rejected.append((rel, "non-regular"))
            continue
        reason, size = inspect_file(path)
        if reason == "ok":
            accepted.append(Candidate(path, rel, size))
        else:
            rejected.append((rel, reason))
    if not accepted:
        raise ImportError(f"no se encontraron archivos de configuración importables en {root}")
    return accepted, rejected


def render_entries(candidates: list[Candidate], scope: dict) -> str:
    lines = [scope["begin"], f"# Generated by core/import_hyprland.py --scope {scope['name']}. Do not edit this block by hand."]
    for candidate in candidates:
        rel = candidate.relative.as_posix()
        source = f"{scope['source_prefix']}/{rel}"
        target = f"{scope['target_prefix']}/{rel}"
        lines.extend(
            [
                "",
                "[[entry]]",
                f"source = {json.dumps(source)}",
                f"target = {json.dumps(target)}",
                'tags = ["hyprland"]',
            ]
        )
    lines.extend([scope["end"], ""])
    return "\n".join(lines)


def replace_generated_block(text: str, block: str, begin: str, end: str) -> str:
    if begin in text or end in text:
        if text.count(begin) != 1 or text.count(end) != 1:
            raise ImportError("manifest contiene marcadores Hyprland inconsistentes")
        start = text.index(begin)
        finish = text.index(end, start) + len(end)
        prefix = text[:start].rstrip()
        suffix = text[finish:].lstrip("\n")
        return f"{prefix}\n\n{block}{suffix}"
    return f"{text.rstrip()}\n\n{block}"


def check_repo_paths_clean(repo: Path, candidates: list[Candidate], scope: dict) -> None:
    paths = ["dotfiles/manifest.toml"] + [
        f"{scope['source_prefix']}/{candidate.relative.as_posix()}" for candidate in candidates
    ]
    proc = subprocess.run(
        ["git", "-C", str(repo), "status", "--porcelain", "--", *paths],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise ImportError(proc.stderr.strip() or "no se pudo consultar git status")
    dirty = proc.stdout.strip()
    if dirty:
        raise ImportError("el área de importación Hyprland ya tiene cambios locales:\n" + dirty)


def validate_manifest(path: Path) -> None:
    with path.open("rb") as handle:
        payload = tomllib.load(handle)
    if payload.get("schema") != 1:
        raise ImportError("manifest resultante tiene schema inválido")
    targets: set[str] = set()
    for entry in payload.get("entry", []):
        target = str(entry.get("target", ""))
        if not target:
            raise ImportError("manifest resultante contiene target vacío")
        if target in targets:
            raise ImportError(f"target duplicado tras importación: {target}")
        targets.add(target)


def print_plan(home: Path, scope: dict, candidates: list[Candidate], rejected: list[tuple[Path, str]]) -> None:
    print(f"Cortetsu Hyprland import ({scope['name']}) · source={scope['active_root'](home)}")
    for item in candidates:
        print(f"  import       {item.relative.as_posix()} ({item.size} B)")
    for rel, reason in rejected:
        mark = "BLOCKED" if reason == "sensitive" else "skip"
        print(f"  {mark:12} {rel.as_posix()} [{reason}]")
    print(f"SUMMARY import={len(candidates)} skipped={len(rejected)}")


def apply(repo: Path, home: Path, scope: dict, candidates: list[Candidate], rejected: list[tuple[Path, str]], commit: bool) -> int:
    sensitive = [rel for rel, reason in rejected if reason == "sensitive"]
    if sensitive:
        joined = ", ".join(path.as_posix() for path in sensitive)
        raise ImportError(f"importación bloqueada por posibles secretos: {joined}")
    check_repo_paths_clean(repo, candidates, scope)
    manifest = repo / "dotfiles/manifest.toml"
    if not manifest.is_file():
        raise ImportError(f"manifest inexistente: {manifest}")
    original_manifest = manifest.read_text(encoding="utf-8")
    block = render_entries(candidates, scope)
    updated_manifest = replace_generated_block(original_manifest, block, scope["begin"], scope["end"])

    # Validate the manifest change before touching any real file, so a bad
    # manifest never leaves file copies orphaned ahead of what it declares.
    manifest_tmp = manifest.with_name(f"{manifest.name}.tmp.{os.getpid()}")
    manifest_tmp.write_text(updated_manifest, encoding="utf-8")
    try:
        validate_manifest(manifest_tmp)
    except Exception:
        manifest_tmp.unlink(missing_ok=True)
        raise

    written: list[Path] = []
    try:
        for candidate in candidates:
            dest = repo / scope["source_prefix"] / candidate.relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            tmp_dest = dest.with_name(f"{dest.name}.tmp.{os.getpid()}")
            shutil.copy2(candidate.source, tmp_dest)
            os.replace(tmp_dest, dest)
            written.append(dest)
        os.replace(manifest_tmp, manifest)
    except Exception:
        manifest_tmp.unlink(missing_ok=True)
        raise

    print(f"IMPORTED hyprland[{scope['name']}]={repo / scope['source_prefix']}")
    print(f"MANIFEST entries={len(candidates)}")
    if rejected:
        print(f"SKIPPED count={len(rejected)}")

    if commit:
        add_paths = ["dotfiles/manifest.toml", *[str(p) for p in written]]
        subprocess.run(["git", "-C", str(repo), "add", "--", *add_paths], check=True)
        diff = subprocess.run(["git", "-C", str(repo), "diff", "--cached", "--quiet"]).returncode
        if diff == 0:
            print("COMMIT skipped=no changes")
        else:
            host = socket.gethostname().split(".")[0]
            stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            subprocess.run(
                [
                    "git", "-C", str(repo), "commit", "-m",
                    f"feat(hyprland): import active {scope['name']} config from {host} ({stamp})",
                ],
                check=True,
            )
            print("COMMIT created=Hyprland import")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely import the active Hyprland tree into Cortetsu dotfiles")
    parser.add_argument("action", choices=("plan", "apply"), nargs="?", default="plan")
    parser.add_argument("--repo")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument(
        "--scope", choices=sorted(SCOPES), default="modules",
        help="modules = ~/.config/hypr/hyprland/* (discovered); core = loader/variables/utils/scheme (fixed set)",
    )
    parser.add_argument("--commit", action="store_true", help="stage only imported Hyprland files and create a local commit")
    args = parser.parse_args()
    repo = repo_root(args.repo)
    home = args.home.expanduser().resolve()
    scope = {**SCOPES[args.scope], "name": args.scope}
    try:
        candidates, rejected = scan(home, scope)
        print_plan(home, scope, candidates, rejected)
        if args.action == "apply":
            return apply(repo, home, scope, candidates, rejected, args.commit)
        return 2 if any(reason == "sensitive" for _, reason in rejected) else 0
    except (ImportError, OSError, subprocess.CalledProcessError, tomllib.TOMLDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
