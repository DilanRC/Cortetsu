#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import re
import stat
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import dotfiles

SCHEMA = 1
SCHEMA_HELPERS = 2
HELPER_NAME = re.compile(r"cortetsu-[A-Za-z0-9_-]{1,110}\Z")
HELPER_BUILD_ID = re.compile(r"helpers-[A-Za-z0-9_-]{1,110}\Z")


class SystemError(RuntimeError):
    pass


def data_root() -> Path:
    return dotfiles.data_root()


def runtime_root() -> Path:
    return Path(os.environ.get("CORTETSU_RUNTIME_ROOT", Path.home() / ".config/quickshell/cortetsu")).expanduser()


def system_root() -> Path:
    return data_root() / "system"


def resolve_link(path: Path) -> Path | None:
    if not path.is_symlink():
        return None
    try:
        return path.resolve(strict=True)
    except OSError:
        return None


def quarantine_generation(generation: Path, root: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    destination_root = root / "invalid"
    destination_root.mkdir(parents=True, exist_ok=True)
    destination = destination_root / f"{generation.name}-{stamp}"
    generation.rename(destination)
    return destination


def atomic_link(target: Path, link: Path) -> None:
    link.parent.mkdir(parents=True, exist_ok=True)
    temporary = link.with_name(f"{link.name}.tmp.{os.getpid()}")
    try:
        temporary.unlink(missing_ok=True)
        os.symlink(str(target), temporary)
        os.replace(temporary, link)
    finally:
        temporary.unlink(missing_ok=True)


def validate_shell(path: Path) -> dict:
    for relative in ("shell.qml", "BUILD_ID", "BUILD.json"):
        if not (path / relative).is_file():
            raise SystemError(f"generación shell inválida, falta {relative}: {path}")
    try:
        payload = json.loads((path / "BUILD.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemError(f"BUILD.json inválido: {path}: {exc}") from exc
    if payload.get("schema") != 1:
        raise SystemError(f"schema shell no soportado: {path}")
    return payload


def validate_dotfiles(path: Path) -> dict:
    try:
        return dotfiles.validate_generation(path)
    except Exception as exc:
        raise SystemError(f"generación dotfiles inválida: {path}: {exc}") from exc


def helpers_root() -> Path:
    return data_root() / "helpers"


def validate_helpers(generation: Path) -> dict:
    """Validate an immutable Rust-compatible HELPERS.json bundle without executing it.

    This does not authorize activation in ~/.local/bin. Python schema-1
    installations remain the default until their install and rollback owners
    have completed the cutover gates.
    """
    builds = helpers_root() / "builds"
    if not generation.is_absolute() or not HELPER_BUILD_ID.fullmatch(generation.name):
        raise SystemError("invalid helpers generation identity")
    if not builds.is_dir() or builds.is_symlink() or generation.parent != builds:
        raise SystemError("helpers generation escapes managed builds")
    if generation.is_symlink() or not generation.is_dir():
        raise SystemError("helpers generation is not a regular directory")
    manifest = generation / "HELPERS.json"
    if manifest.is_symlink() or not manifest.is_file() or manifest.stat().st_size > 1024 * 1024:
        raise SystemError("missing or unsafe helper manifest")
    try:
        meta = json.loads(manifest.read_text(encoding="utf-8"))
    except (ValueError, OSError) as exc:
        raise SystemError("invalid helper manifest") from exc
    entries = meta.get("helpers")
    if meta.get("schema") != 1 or meta.get("build_id") != generation.name or not isinstance(entries, list) or not 1 <= len(entries) <= 128:
        raise SystemError("unsupported helper manifest")
    names = set()
    total = 0
    for entry in entries:
        if not isinstance(entry, dict):
            raise SystemError("invalid helper manifest entry")
        name = entry.get("name")
        size = entry.get("bytes")
        expected = entry.get("sha256")
        if (not isinstance(name, str) or not HELPER_NAME.fullmatch(name) or name in names
            or type(size) is not int or not 0 <= size <= 32 * 1024 * 1024
            or not isinstance(expected, str) or re.fullmatch(r"[0-9a-fA-F]{64}", expected) is None):
            raise SystemError("invalid helper metadata")
        names.add(name)
        file = generation / name
        try:
            details = file.lstat()
        except OSError as exc:
            raise SystemError("missing helper executable") from exc
        if not stat.S_ISREG(details.st_mode) or details.st_size != size or details.st_mode & 0o111 == 0:
            raise SystemError("invalid helper executable")
        digest = hashlib.sha256()
        with file.open("rb") as handle:
            for chunk in iter(lambda: handle.read(64 * 1024), b""):
                digest.update(chunk)
        if digest.hexdigest() != expected.lower():
            raise SystemError("helper digest mismatch")
        total += size
        if total > 128 * 1024 * 1024:
            raise SystemError("helpers generation too large")
    if {item.name for item in generation.iterdir()} != names | {"HELPERS.json"}:
        raise SystemError("unexpected helper bundle entries")
    return meta


def current_helpers() -> Path | None:
    return resolve_link(helpers_root() / "current")


def generation_payload(path: Path) -> dict:
    file = path / "SYSTEM.json"
    if not file.is_file():
        raise SystemError(f"generación de sistema sin SYSTEM.json: {path}")
    try:
        payload = json.loads(file.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise SystemError(f"SYSTEM.json inválido: {path}: {exc}") from exc
    if payload.get("schema") not in (SCHEMA, SCHEMA_HELPERS):
        raise SystemError(f"schema de sistema no soportado: {path}")
    return payload


def validate_system(path: Path) -> dict:
    payload = generation_payload(path)
    shell = Path(str(payload.get("shellGeneration", "")))
    dots = Path(str(payload.get("dotfilesGeneration", "")))
    if not shell.is_absolute() or not dots.is_absolute():
        raise SystemError(f"SYSTEM.json contiene rutas no absolutas: {path}")
    validate_shell(shell)
    validate_dotfiles(dots)
    if payload["schema"] == SCHEMA_HELPERS:
        candidate = Path(str(payload.get("helpersGeneration", "")))
        if not candidate.is_absolute():
            raise SystemError("schema 2 requires absolute helpersGeneration")
        validate_helpers(candidate)
    elif "helpersGeneration" in payload:
        raise SystemError("schema 1 must not declare helpersGeneration")
    return payload


def current_components() -> tuple[Path, Path]:
    shell = resolve_link(runtime_root() / "current")
    dots = resolve_link(data_root() / "dotfiles/current")
    if shell is None:
        raise SystemError("no existe shell current administrado")
    if dots is None:
        raise SystemError("no existe dotfiles current administrado")
    validate_shell(shell)
    validate_dotfiles(dots)
    return shell, dots


def repo_revision(repo: Path) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def build_id() -> str:
    return datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S") + f"-{os.getpid()}"


def promote(repo: Path) -> int:
    root = system_root()
    root.mkdir(parents=True, exist_ok=True)
    with (root / "system.lock").open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        return _promote(repo)


def _promote(repo: Path) -> int:
    shell, dots = current_components()
    root = system_root()
    builds = root / "builds"
    builds.mkdir(parents=True, exist_ok=True)
    generation = builds / build_id()
    generation.mkdir()
    payload = {
        "schema": SCHEMA,
        "buildId": generation.name,
        "builtAt": datetime.now(timezone.utc).isoformat(),
        "repositoryRevision": repo_revision(repo),
        "shellGeneration": str(shell),
        "dotfilesGeneration": str(dots),
    }
    (generation / "SYSTEM.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    validate_system(generation)

    current = root / "current"
    previous = root / "previous"
    old_current = resolve_link(current)
    invalid_current = False
    if old_current is not None:
        try:
            validate_system(old_current)
        except SystemError:
            invalid_current = True
        else:
            atomic_link(old_current, previous)
    atomic_link(generation, current)
    verify(repo)
    quarantined = None
    if invalid_current and old_current is not None:
        quarantined = quarantine_generation(old_current, root)
    print(f"PROMOTED system={generation}")
    if old_current is not None:
        print(f"PREVIOUS system={old_current}")
    if quarantined is not None:
        print(f"QUARANTINED invalid={quarantined}")
    return 0


def verify(repo: Path) -> int:
    current = resolve_link(system_root() / "current")
    if current is None:
        raise SystemError("no existe generación de sistema current")
    payload = validate_system(current)
    shell, dots = current_components()
    expected_shell = Path(payload["shellGeneration"])
    expected_dots = Path(payload["dotfilesGeneration"])
    if shell != expected_shell:
        raise SystemError(f"system/shell drift: current={shell} expected={expected_shell}")
    if dots != expected_dots:
        raise SystemError(f"system/dotfiles drift: current={dots} expected={expected_dots}")
    if payload["schema"] == SCHEMA_HELPERS:
        active_helpers = current_helpers()
        expected_helpers = Path(payload["helpersGeneration"])
        if active_helpers != expected_helpers:
            raise SystemError(f"system/helpers drift: current={active_helpers} expected={expected_helpers}")
    elif current_helpers() is not None:
        raise SystemError("schema 1 cannot silently own an active helpers generation")
    print(f"PASS: system generation {current}")
    return 0


def status(repo: Path) -> int:
    root = system_root()
    print("System generations:")
    for label in ("current", "previous"):
        resolved = resolve_link(root / label)
        print(f"  {label}={resolved or 'missing'}")
        if resolved is not None:
            try:
                payload = validate_system(resolved)
            except Exception as exc:
                print(f"  {label}_metadata=invalid ({exc})")
            else:
                print(f"  {label}_shell={payload['shellGeneration']}")
                print(f"  {label}_dotfiles={payload['dotfilesGeneration']}")
                if payload["schema"] == SCHEMA_HELPERS:
                    print(f"  {label}_helpers={payload['helpersGeneration']}")
                print(f"  {label}_revision={payload.get('repositoryRevision', 'unknown')}")
    return 0


def rollback(repo: Path) -> int:
    root = system_root()
    lock_path = root / "system.lock"
    root.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        current_meta = resolve_link(root / "current")
        previous_meta = resolve_link(root / "previous")
        if current_meta is None or previous_meta is None:
            raise SystemError("rollback de sistema requiere current y previous")
        current_payload = validate_system(current_meta)
        target_payload = validate_system(previous_meta)
        if current_payload["schema"] != target_payload["schema"]:
            raise SystemError("rollback across helper schema boundary requires a separate verified migration")
        if current_payload["schema"] == SCHEMA_HELPERS:
            # Rust's journaled transaction is the only authorized writer for
            # schema 2. Avoid a six-pointer Python rollback that leaves
            # helpers/current pointing at the wrong executable generation.
            raise SystemError("schema 2 rollback requires the Rust journaled recovery owner")
        if current_helpers() is not None:
            raise SystemError("schema 1 rollback refused while helpers/current exists")

        old_shell, old_dots = current_components()
        target_shell = Path(target_payload["shellGeneration"])
        target_dots = Path(target_payload["dotfilesGeneration"])
        validate_shell(target_shell)
        validate_dotfiles(target_dots)

        shell_current = runtime_root() / "current"
        shell_previous = runtime_root() / "previous"
        dots_current = data_root() / "dotfiles/current"
        dots_previous = data_root() / "dotfiles/previous"
        try:
            atomic_link(old_shell, shell_previous)
            atomic_link(target_shell, shell_current)
            atomic_link(old_dots, dots_previous)
            atomic_link(target_dots, dots_current)
            atomic_link(current_meta, root / "previous")
            atomic_link(previous_meta, root / "current")
            verify(repo)
        except Exception:
            atomic_link(old_shell, shell_current)
            atomic_link(old_dots, dots_current)
            atomic_link(current_meta, root / "current")
            atomic_link(previous_meta, root / "previous")
            raise

        print(
            "ROLLED BACK system "
            f"current={previous_meta} previous={current_meta} "
            f"shell={target_shell} dotfiles={target_dots}"
        )
    return 0


def gc(repo: Path, keep: int) -> int:
    # A per-layer collector cannot see which shell and dotfiles generations a
    # retained system generation still references. Only the coordinator may
    # plan deletions; this action stays as a read-only pointer to it.
    print("GC system: sin borrados; la recolección es coordinada y explícita.")
    print(f"Revisa el plan con: cortetsu gc --keep {keep}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Cortetsu unified system generations")
    parser.add_argument("action", choices=("promote", "verify", "status", "rollback", "gc"))
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--keep", type=int, default=3)
    args = parser.parse_args()
    repo = args.repo.resolve()
    try:
        if args.action == "promote":
            return promote(repo)
        if args.action == "verify":
            return verify(repo)
        if args.action == "status":
            return status(repo)
        if args.action == "rollback":
            return rollback(repo)
        return gc(repo, args.keep)
    except (SystemError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
