#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import tomllib
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Iterable

SCHEMA = 1
HYPRLAND_LOADER_TARGET = ".config/hypr/hyprland.lua"


class DotfilesError(RuntimeError):
    pass


@dataclass(frozen=True)
class Entry:
    source: str
    target: str
    tags: tuple[str, ...]


def data_root() -> Path:
    return Path(os.environ.get("CORTETSU_DATA_ROOT", Path.home() / ".local/share/cortetsu")).expanduser()


def manifest_path(repo: Path) -> Path:
    return repo / "dotfiles/manifest.toml"


def read_toml(path: Path) -> dict:
    with path.open("rb") as handle:
        return tomllib.load(handle)


def safe_relative(value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or any(part == ".." for part in path.parts):
        raise DotfilesError(f"ruta no permitida en manifest: {value}")
    if not value or value == ".":
        raise DotfilesError("ruta vacía en manifest")
    return path


def dedupe(values: Iterable[str]) -> list[str]:
    seen: set[str] = set()
    result: list[str] = []
    for value in values:
        if value not in seen:
            seen.add(value)
            result.append(value)
    return result


def load_profile(repo: Path, name: str, seen: set[str] | None = None) -> dict:
    seen = set() if seen is None else set(seen)
    if name in seen:
        raise DotfilesError(f"ciclo de perfiles detectado: {name}")
    seen.add(name)
    path = repo / "profiles" / f"{name}.toml"
    if not path.is_file():
        raise DotfilesError(f"perfil inexistente: {path}")
    raw = read_toml(path)
    if raw.get("schema") != SCHEMA:
        raise DotfilesError(f"schema de perfil no soportado: {path}")

    tags: list[str] = []
    package_groups: list[str] = []
    for parent in raw.get("inherits", []):
        inherited = load_profile(repo, str(parent), seen)
        tags.extend(inherited["enabled_tags"])
        package_groups.extend(inherited["package_groups"])
    tags.extend(str(item) for item in raw.get("enabled_tags", []))
    package_groups.extend(str(item) for item in raw.get("package_groups", []))
    return {
        "name": str(raw.get("name", name)),
        "enabled_tags": dedupe(tags),
        "package_groups": dedupe(package_groups),
    }


def load_manifest(repo: Path, profile_override: str | None = None) -> tuple[dict, dict, list[Entry]]:
    path = manifest_path(repo)
    if not path.is_file():
        raise DotfilesError(f"manifest de dotfiles inexistente: {path}")
    raw = read_toml(path)
    if raw.get("schema") != SCHEMA:
        raise DotfilesError(f"schema de dotfiles no soportado: {raw.get('schema')}")
    default_profile = str(raw.get("defaults", {}).get("profile", "personal"))
    profile_name = profile_override or os.environ.get("CORTETSU_PROFILE") or default_profile
    profile = load_profile(repo, profile_name)
    enabled = set(profile["enabled_tags"])
    entries: list[Entry] = []
    seen_targets: set[str] = set()
    for item in raw.get("entry", []):
        source = str(item["source"])
        target = str(item["target"])
        safe_relative(source)
        safe_relative(target)
        tags = tuple(str(tag) for tag in item.get("tags", []))
        if tags and enabled.isdisjoint(tags):
            continue
        if target in seen_targets:
            raise DotfilesError(f"target duplicado en manifest: {target}")
        seen_targets.add(target)
        src_path = repo / source
        if not src_path.exists():
            raise DotfilesError(f"source inexistente: {src_path}")
        entries.append(Entry(source=source, target=target, tags=tags))
    if not entries:
        raise DotfilesError(f"el perfil {profile_name} no selecciona ningún dotfile")
    return raw, profile, entries


def hash_path(path: Path) -> str:
    digest = hashlib.sha256()
    if path.is_symlink():
        digest.update(b"L\0")
        digest.update(os.readlink(path).encode())
    elif path.is_file():
        digest.update(b"F\0")
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    elif path.is_dir():
        digest.update(b"D\0")
        for child in sorted(path.rglob("*"), key=lambda p: p.as_posix()):
            rel = child.relative_to(path).as_posix().encode()
            digest.update(rel + b"\0" + hash_path(child).encode() + b"\0")
    else:
        raise DotfilesError(f"no se puede hashear: {path}")
    return digest.hexdigest()


def copy_source(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    elif source.is_symlink():
        os.symlink(os.readlink(source), destination)
    else:
        shutil.copy2(source, destination)


def repo_revision(repo: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def generation_id(repo: Path) -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    revision = repo_revision(repo)
    short = revision[:8] if revision != "unknown" else "unknown"
    return f"{stamp}-{os.getpid()}-{short}"


def build_generation(repo: Path, profile_name: str | None = None) -> Path:
    _, profile, entries = load_manifest(repo, profile_name)
    root = data_root() / "dotfiles/builds"
    root.mkdir(parents=True, exist_ok=True)
    build_id = generation_id(repo)
    staging = root / f".staging-{build_id}"
    final = root / build_id
    if staging.exists() or final.exists():
        raise DotfilesError(f"generación ya existente: {build_id}")
    staging.mkdir(parents=True)
    records: list[dict] = []
    try:
        for entry in entries:
            source = repo / entry.source
            destination = staging / "home" / safe_relative(entry.target)
            copy_source(source, destination)
            records.append({
                "source": entry.source,
                "target": entry.target,
                "tags": list(entry.tags),
                "sha256": hash_path(destination),
            })
        payload = {
            "schema": SCHEMA,
            "buildId": build_id,
            "builtAt": datetime.now(timezone.utc).isoformat(),
            "repositoryRevision": repo_revision(repo),
            "profile": profile["name"],
            "entries": records,
        }
        (staging / "MANIFEST.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        staging.rename(final)
    except Exception:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return final


def generation_payload(generation: Path) -> dict:
    path = generation / "MANIFEST.json"
    if not path.is_file():
        raise DotfilesError(f"generación sin MANIFEST.json: {generation}")
    payload = json.loads(path.read_text(encoding="utf-8"))
    if payload.get("schema") != SCHEMA:
        raise DotfilesError(f"schema de generación no soportado: {generation}")
    return payload


def validate_generation(generation: Path) -> dict:
    payload = generation_payload(generation)
    for item in payload.get("entries", []):
        path = generation / "home" / safe_relative(str(item["target"]))
        if not path.exists() and not path.is_symlink():
            raise DotfilesError(f"falta target en generación: {path}")
        actual = hash_path(path)
        if actual != item.get("sha256"):
            raise DotfilesError(f"hash inválido en generación: {path}")
    return payload


def atomic_symlink(target: Path, link: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name(f"{link.name}.tmp.{os.getpid()}")
    try:
        temporary.unlink(missing_ok=True)
        os.symlink(str(target), temporary)
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)


def stable_loader_text(stable: Path) -> str:
    """Keep Hyprland's config filename stable across generation promotion."""
    encoded = json.dumps(str(stable))
    return (
        "-- Cortetsu stable loader; the target is promoted atomically.\n"
        f"dofile({encoded})\n"
    )


def points_to_stable_loader(target: Path, stable: Path) -> bool:
    if target.is_symlink() or not target.is_file() or target.name != "hyprland.lua":
        return False
    try:
        return target.read_text(encoding="utf-8") == stable_loader_text(stable)
    except OSError:
        return False


def resolved_link(link: Path) -> Path | None:
    if not link.is_symlink():
        return None
    try:
        return link.resolve(strict=True)
    except OSError:
        return None


def quarantine_generation(generation: Path, data: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    root = data / "dotfiles" / "invalid"
    root.mkdir(parents=True, exist_ok=True)
    destination = root / f"{generation.name}-{stamp}"
    generation.rename(destination)
    return destination


def stable_target(data: Path, target: str) -> Path:
    return data / "dotfiles/current/home" / safe_relative(target)


def points_to_stable(target_path: Path, stable: Path) -> bool:
    if target_path.name == "hyprland.lua":
        return points_to_stable_loader(target_path, stable)
    if not target_path.is_symlink():
        return False
    raw = Path(os.readlink(target_path))
    absolute = raw if raw.is_absolute() else target_path.parent / raw
    return os.path.normpath(str(absolute)) == os.path.normpath(str(stable))


def backup_path(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        os.symlink(os.readlink(source), destination)
    elif source.is_dir():
        shutil.copytree(source, destination, symlinks=True)
    else:
        shutil.copy2(source, destination)


def restore_backup(backup: Path | None, target: Path) -> None:
    if target.is_symlink() or target.is_file():
        target.unlink(missing_ok=True)
    elif target.exists():
        shutil.rmtree(target)
    if backup is None:
        return
    target.parent.mkdir(parents=True, exist_ok=True)
    backup_path(backup, target)


def plan(repo: Path, profile_name: str | None = None) -> int:
    _, profile, entries = load_manifest(repo, profile_name)
    data = data_root()
    print(f"Cortetsu dotfiles plan · profile={profile['name']}")
    for entry in entries:
        target = Path.home() / safe_relative(entry.target)
        stable = stable_target(data, entry.target)
        if points_to_stable(target, stable):
            action = "managed"
        elif target.exists() or target.is_symlink():
            action = "backup+adopt"
        else:
            action = "create"
        print(f"  {action:12} {entry.target} <- {entry.source}")
    return 0


def apply(repo: Path, profile_name: str | None = None) -> int:
    _, profile, entries = load_manifest(repo, profile_name)
    data = data_root()
    dot_root = data / "dotfiles"
    current = dot_root / "current"
    previous = dot_root / "previous"
    backups = dot_root / "backups"
    generation = build_generation(repo, profile_name)
    validate_generation(generation)

    old_current = resolved_link(current)
    old_previous = resolved_link(previous)
    invalid_current = False
    if old_current is not None:
        try:
            validate_generation(old_current)
        except DotfilesError:
            invalid_current = True
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    backup_root = backups / stamp
    backup_map: dict[Path, Path | None] = {}
    changed: list[Path] = []

    for entry in entries:
        target = Path.home() / safe_relative(entry.target)
        stable = stable_target(data, entry.target)
        if points_to_stable(target, stable):
            continue
        if target.exists() and target.is_dir() and not target.is_symlink():
            raise DotfilesError(f"no se adopta un directorio completo automáticamente: {target}")
        if target.exists() or target.is_symlink():
            backup = backup_root / "home" / safe_relative(entry.target)
            backup_path(target, backup)
            backup_map[target] = backup
        else:
            backup_map[target] = None

    try:
        if old_current is not None and not invalid_current:
            validate_generation(old_current)
            atomic_symlink(old_current, previous)
        atomic_symlink(generation, current)

        for entry in entries:
            target = Path.home() / safe_relative(entry.target)
            stable = stable_target(data, entry.target)
            if points_to_stable(target, stable):
                continue
            target.parent.mkdir(parents=True, exist_ok=True)
            temporary = target.with_name(f"{target.name}.tmp.{os.getpid()}")
            temporary.unlink(missing_ok=True)
            if entry.target == HYPRLAND_LOADER_TARGET:
                temporary.write_text(stable_loader_text(stable), encoding="utf-8")
            else:
                os.symlink(str(stable), temporary)
            os.replace(temporary, target)
            changed.append(target)
    except Exception:
        if old_current is not None:
            atomic_symlink(old_current, current)
        else:
            current.unlink(missing_ok=True)
        if old_previous is not None:
            atomic_symlink(old_previous, previous)
        else:
            previous.unlink(missing_ok=True)
        for target in reversed(changed):
            restore_backup(backup_map.get(target), target)
        raise

    quarantined = None
    if invalid_current and old_current is not None:
        quarantined = quarantine_generation(old_current, data)

    if not any(backup_root.rglob("*")) if backup_root.exists() else True:
        shutil.rmtree(backup_root, ignore_errors=True)
    print(f"PROMOTED dotfiles={generation}")
    print(f"PROFILE profile={profile['name']}")
    if old_current is not None:
        print(f"PREVIOUS dotfiles={old_current}")
    if backup_root.exists():
        print(f"BACKUP unmanaged={backup_root}")
    if quarantined is not None:
        print(f"QUARANTINED invalid={quarantined}")
    return 0


def verify(repo: Path, profile_name: str | None = None) -> int:
    _, profile, entries = load_manifest(repo, profile_name)
    data = data_root()
    current = data / "dotfiles/current"
    generation = resolved_link(current)
    if generation is None:
        raise DotfilesError(f"no existe generación de dotfiles current: {current}")
    payload = validate_generation(generation)
    if payload.get("profile") != profile["name"]:
        raise DotfilesError(f"perfil promovido={payload.get('profile')} esperado={profile['name']}")
    for entry in entries:
        target = Path.home() / safe_relative(entry.target)
        stable = stable_target(data, entry.target)
        if not points_to_stable(target, stable):
            raise DotfilesError(f"target no administrado por Cortetsu: {target}")
        if not target.exists():
            raise DotfilesError(f"target administrado roto: {target}")
    print(f"PASS: dotfiles generation {generation}")
    return 0


def status(repo: Path, profile_name: str | None = None) -> int:
    _, profile, entries = load_manifest(repo, profile_name)
    data = data_root()
    current = resolved_link(data / "dotfiles/current")
    previous = resolved_link(data / "dotfiles/previous")
    print("Dotfiles generations:")
    print(f"  profile={profile['name']}")
    print(f"  current={current or 'missing'}")
    print(f"  previous={previous or 'missing'}")
    managed = 0
    for entry in entries:
        target = Path.home() / safe_relative(entry.target)
        if points_to_stable(target, stable_target(data, entry.target)):
            managed += 1
    print(f"  managed_targets={managed}/{len(entries)}")
    return 0


def rollback(repo: Path, profile_name: str | None = None) -> int:
    load_manifest(repo, profile_name)
    data = data_root()
    current_link = data / "dotfiles/current"
    previous_link = data / "dotfiles/previous"
    current = resolved_link(current_link)
    previous = resolved_link(previous_link)
    if current is None or previous is None:
        raise DotfilesError("rollback requiere current y previous")
    validate_generation(current)
    validate_generation(previous)
    atomic_symlink(previous, current_link)
    atomic_symlink(current, previous_link)
    verify(repo, profile_name)
    print(f"ROLLED BACK dotfiles current={previous} previous={current}")
    return 0


def gc(repo: Path, keep: int, profile_name: str | None = None) -> int:
    load_manifest(repo, profile_name)
    root = data_root() / "dotfiles/builds"
    root.mkdir(parents=True, exist_ok=True)
    protected = {
        p for p in (
            resolved_link(data_root() / "dotfiles/current"),
            resolved_link(data_root() / "dotfiles/previous"),
        ) if p is not None
    }
    builds = sorted((p for p in root.iterdir() if p.is_dir() and not p.name.startswith(".staging-")), key=lambda p: p.name, reverse=True)
    retained = set(builds[: max(keep, 0)]) | protected
    removed = 0
    for build in builds:
        if build not in retained:
            shutil.rmtree(build)
            removed += 1
    print(f"GC removed={removed} retained={len(retained)}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Cortetsu immutable dotfiles generations")
    parser.add_argument("action", choices=("plan", "apply", "verify", "status", "rollback", "gc"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--profile")
    parser.add_argument("--keep", type=int, default=3)
    args = parser.parse_args()
    repo = args.repo.resolve()
    try:
        if args.action == "plan":
            return plan(repo, args.profile)
        if args.action == "apply":
            return apply(repo, args.profile)
        if args.action == "verify":
            return verify(repo, args.profile)
        if args.action == "status":
            return status(repo, args.profile)
        if args.action == "rollback":
            return rollback(repo, args.profile)
        return gc(repo, args.keep, args.profile)
    except (DotfilesError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
