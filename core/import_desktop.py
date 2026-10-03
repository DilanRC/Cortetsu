#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import socket
import subprocess
import tempfile
import tomllib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

BEGIN = "# BEGIN CORTETSU DESKTOP IMPORT"
END = "# END CORTETSU DESKTOP IMPORT"
MAX_BYTES = 2 * 1024 * 1024
SKIP_DIRS = {".git", "backup", "backups", "cache", "logs", "tmp", "temp"}
SKIP_SUFFIXES = (".bak", ".old", ".orig", ".tmp", ".swp", ".swo", ".lock", ".log", "~")
SENSITIVE = re.compile(
    r"(?i)\b(password|passwd|api[_-]?key|access[_-]?token|refresh[_-]?token|client[_-]?secret|secret[_-]?access[_-]?key|private[_-]?key)\b\s*[:=]"
)
PRIVATE_KEY_MARKERS = ("BEGIN OPENSSH PRIVATE KEY", "BEGIN RSA PRIVATE KEY", "BEGIN EC PRIVATE KEY", "BEGIN PRIVATE KEY")
GROUPS = ("kitty", "zsh", "gtk", "qt")
THEME_OWNED_TARGETS = {
    Path(".config/kitty/caelestia-theme.conf"),
    Path(".config/kitty/cortetsu-theme.conf"),
    Path(".config/gtk-3.0/cortetsu-colors.css"),
    Path(".config/gtk-4.0/cortetsu-colors.css"),
}
DIR_SPECS = (
    ("kitty", "terminal", ".config/kitty"),
    ("zsh", "user-shell", ".config/zsh"),
    ("gtk", "toolkit", ".config/gtk-3.0"),
    ("gtk", "toolkit", ".config/gtk-4.0"),
    ("qt", "toolkit", ".config/qt5ct"),
    ("qt", "toolkit", ".config/qt6ct"),
    ("qt", "toolkit", ".config/Kvantum"),
)
FILE_SPECS = (
    ("zsh", "user-shell", ".zshrc"),
    ("zsh", "user-shell", ".zprofile"),
    ("zsh", "user-shell", ".zshenv"),
    ("zsh", "user-shell", ".zlogin"),
    ("gtk", "toolkit", ".gtkrc-2.0"),
    ("qt", "toolkit", ".config/kdeglobals"),
)


class ImportError(RuntimeError):
    pass


@dataclass(frozen=True)
class Candidate:
    source: Path
    target: Path
    group: str
    tag: str
    size: int


def repo_root(value: str | None) -> Path:
    if value:
        return Path(value).expanduser().resolve()
    return Path(__file__).resolve().parents[1]


def manifest_path(repo: Path) -> Path:
    return repo / "dotfiles/manifest.toml"


def imported_root(repo: Path) -> Path:
    return repo / "dotfiles/imported/desktop"


def is_backupish(path: Path) -> bool:
    lowered = path.name.lower()
    if any(part.lower() in SKIP_DIRS or part.lower().startswith("legacy-backup") for part in path.parts):
        return True
    return lowered.endswith(SKIP_SUFFIXES) or ".backup" in lowered


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
    if SENSITIVE.search(text) or any(marker in text for marker in PRIVATE_KEY_MARKERS):
        return "sensitive", size
    return "ok", size


def add_candidate(
    path: Path,
    home: Path,
    group: str,
    tag: str,
    accepted: list[Candidate],
    rejected: list[tuple[str, Path, str]],
) -> None:
    target = path.relative_to(home)
    if target == Path(".config/kdeglobals"):
        rejected.append((group, target, "user-owned"))
        return
    if target in THEME_OWNED_TARGETS:
        rejected.append((group, target, "theme-owned"))
        return
    if is_backupish(target):
        rejected.append((group, target, "backup/temp"))
        return
    if path.is_symlink():
        rejected.append((group, target, "symlink"))
        return
    if not path.is_file():
        rejected.append((group, target, "non-regular"))
        return
    reason, size = inspect_file(path)
    if reason == "ok":
        accepted.append(Candidate(path, target, group, tag, size))
    else:
        rejected.append((group, target, reason))


def scan(home: Path, selected_groups: set[str]) -> tuple[list[Candidate], list[tuple[str, Path, str]]]:
    accepted: list[Candidate] = []
    rejected: list[tuple[str, Path, str]] = []
    seen: set[Path] = set()

    for group, tag, relative in DIR_SPECS:
        if group not in selected_groups:
            continue
        root = home / relative
        if not root.exists():
            rejected.append((group, Path(relative), "missing"))
            continue
        if root.is_symlink():
            rejected.append((group, Path(relative), "symlink-root"))
            continue
        if not root.is_dir():
            rejected.append((group, Path(relative), "not-directory"))
            continue
        found = False
        for path in sorted(root.rglob("*"), key=lambda item: item.as_posix()):
            rel_to_root = path.relative_to(root)
            if is_backupish(rel_to_root):
                if path.is_file() or path.is_symlink():
                    rejected.append((group, path.relative_to(home), "backup/temp"))
                continue
            if path.is_dir():
                continue
            found = True
            target = path.relative_to(home)
            if target in seen:
                continue
            seen.add(target)
            add_candidate(path, home, group, tag, accepted, rejected)
        if not found:
            rejected.append((group, Path(relative), "empty"))

    for group, tag, relative in FILE_SPECS:
        if group not in selected_groups:
            continue
        path = home / relative
        if not path.exists() and not path.is_symlink():
            rejected.append((group, Path(relative), "missing"))
            continue
        target = path.relative_to(home)
        if target in seen:
            continue
        seen.add(target)
        add_candidate(path, home, group, tag, accepted, rejected)

    accepted.sort(key=lambda item: item.target.as_posix())
    rejected.sort(key=lambda item: (item[0], item[1].as_posix(), item[2]))
    if not accepted:
        raise ImportError("no se encontraron configuraciones de escritorio importables")
    return accepted, rejected


def render_entries(candidates: list[Candidate]) -> str:
    lines = [BEGIN, "# Generated by core/import_desktop.py. Re-run the importer instead of editing this block by hand."]
    for candidate in candidates:
        target = candidate.target.as_posix()
        source = f"dotfiles/imported/desktop/home/{target}"
        lines.extend(
            [
                "",
                "[[entry]]",
                f"source = {json.dumps(source)}",
                f"target = {json.dumps(target)}",
                f"tags = [{json.dumps(candidate.tag)}]",
            ]
        )
    lines.extend([END, ""])
    return "\n".join(lines)


def replace_generated_block(text: str, block: str) -> str:
    if BEGIN in text or END in text:
        if text.count(BEGIN) != 1 or text.count(END) != 1:
            raise ImportError("manifest contiene marcadores desktop inconsistentes")
        start = text.index(BEGIN)
        finish = text.index(END, start) + len(END)
        prefix = text[:start].rstrip()
        suffix = text[finish:].lstrip("\n")
        return f"{prefix}\n\n{block}{suffix}"
    return f"{text.rstrip()}\n\n{block}"


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


def check_repo_paths_clean(repo: Path) -> None:
    paths = ["dotfiles/manifest.toml", "dotfiles/imported/desktop"]
    proc = subprocess.run(
        ["git", "-C", str(repo), "status", "--porcelain", "--", *paths],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.returncode != 0:
        raise ImportError(proc.stderr.strip() or "no se pudo consultar git status")
    if proc.stdout.strip():
        raise ImportError("el área de importación desktop ya tiene cambios locales:\n" + proc.stdout.strip())


def normalise_imported_text(candidate: Candidate, text: str) -> str:
    if candidate.target == Path(".config/kitty/kitty.conf"):
        kept = []
        for line in text.splitlines():
            lowered = line.strip().lower()
            if lowered.startswith("include ") and (
                "caelestia-theme.conf" in lowered
                or "state/caelestia/theme/kitty" in lowered
                or "kitty-caerice.conf" in lowered
                or "cortetsu-theme.conf" in lowered
            ):
                continue
            if "caerice:" in lowered or "cortetsu: caelestia active scheme" in lowered:
                continue
            kept.append(line)
        body = "\n".join(kept).strip("\n")
        return "include cortetsu-theme.conf\n\n" + body + "\n"
    if candidate.target in {Path(".config/gtk-3.0/gtk.css"), Path(".config/gtk-4.0/gtk.css")}:
        lines = [
            line
            for line in text.splitlines()
            if not line.lstrip().startswith("@define-color ")
            and 'cortetsu-colors.css' not in line
        ]
        body = "\n".join(lines).strip("\n")
        return '@import "cortetsu-colors.css";\n' + (body + "\n" if body else "")
    return text


def copy_candidate(candidate: Candidate, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    try:
        text = candidate.source.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        shutil.copy2(candidate.source, out)
        return
    out.write_text(normalise_imported_text(candidate, text), encoding="utf-8")
    shutil.copymode(candidate.source, out)


def print_plan(home: Path, candidates: list[Candidate], rejected: list[tuple[str, Path, str]]) -> None:
    print(f"Cortetsu desktop import · home={home}")
    for item in candidates:
        print(f"  import       [{item.group:5}] {item.target.as_posix()} ({item.size} B)")
    for group, target, reason in rejected:
        mark = "BLOCKED" if reason == "sensitive" else "skip"
        print(f"  {mark:12} [{group:5}] {target.as_posix()} [{reason}]")
    counts = {group: sum(1 for item in candidates if item.group == group) for group in GROUPS}
    print("SUMMARY " + " ".join(f"{group}={counts[group]}" for group in GROUPS) + f" skipped={len(rejected)}")


def apply(repo: Path, home: Path, candidates: list[Candidate], rejected: list[tuple[str, Path, str]], commit: bool) -> int:
    sensitive = [target for _, target, reason in rejected if reason == "sensitive"]
    if sensitive:
        raise ImportError("importación bloqueada por posibles secretos: " + ", ".join(path.as_posix() for path in sensitive))

    check_repo_paths_clean(repo)
    manifest = manifest_path(repo)
    if not manifest.is_file():
        raise ImportError(f"manifest inexistente: {manifest}")
    original_manifest = manifest.read_text(encoding="utf-8")
    updated_manifest = replace_generated_block(original_manifest, render_entries(candidates))

    destination = imported_root(repo)
    destination.parent.mkdir(parents=True, exist_ok=True)
    backup = destination.with_name(f"{destination.name}.previous.{os.getpid()}")
    if backup.exists():
        shutil.rmtree(backup)

    with tempfile.TemporaryDirectory(prefix="cortetsu-desktop-import-", dir=destination.parent) as tmp:
        staging = Path(tmp) / "desktop"
        stage_home = staging / "home"
        stage_home.mkdir(parents=True)
        for candidate in candidates:
            out = stage_home / candidate.target
            copy_candidate(candidate, out)

        manifest_tmp = manifest.with_name(f"{manifest.name}.tmp.{os.getpid()}")
        manifest_tmp.write_text(updated_manifest, encoding="utf-8")
        validate_manifest(manifest_tmp)
        try:
            if destination.exists():
                destination.rename(backup)
            staging.rename(destination)
            os.replace(manifest_tmp, manifest)
        except Exception:
            manifest_tmp.unlink(missing_ok=True)
            manifest.write_text(original_manifest, encoding="utf-8")
            if destination.exists():
                shutil.rmtree(destination)
            if backup.exists():
                backup.rename(destination)
            raise
        else:
            shutil.rmtree(backup, ignore_errors=True)

    print(f"IMPORTED desktop={destination}")
    print(f"MANIFEST entries={len(candidates)}")
    if rejected:
        print(f"SKIPPED count={len(rejected)}")

    if commit:
        subprocess.run(
            ["git", "-C", str(repo), "add", "--", "dotfiles/manifest.toml", "dotfiles/imported/desktop"],
            check=True,
        )
        diff = subprocess.run(["git", "-C", str(repo), "diff", "--cached", "--quiet"]).returncode
        if diff == 0:
            print("COMMIT skipped=no changes")
        else:
            host = socket.gethostname().split(".")[0]
            stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d")
            subprocess.run(
                ["git", "-C", str(repo), "commit", "-m", f"feat(dotfiles): import desktop config from {host} ({stamp})"],
                check=True,
            )
            print("COMMIT created=desktop import")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Safely import Kitty, Zsh, GTK and Qt config into Cortetsu")
    parser.add_argument("action", choices=("plan", "apply"), nargs="?", default="plan")
    parser.add_argument("--repo")
    parser.add_argument("--home", type=Path, default=Path.home())
    parser.add_argument("--group", action="append", choices=GROUPS, help="limit import to one or more groups")
    parser.add_argument("--commit", action="store_true", help="stage only imported desktop files and create a local commit")
    args = parser.parse_args()
    repo = repo_root(args.repo)
    home = args.home.expanduser().resolve()
    selected = set(args.group or GROUPS)
    try:
        candidates, rejected = scan(home, selected)
        print_plan(home, candidates, rejected)
        if args.action == "apply":
            return apply(repo, home, candidates, rejected, args.commit)
        return 2 if any(reason == "sensitive" for _, _, reason in rejected) else 0
    except (ImportError, OSError, subprocess.CalledProcessError, tomllib.TOMLDecodeError) as exc:
        print(f"ERROR: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
