#!/usr/bin/env python3
"""Plan and safely collect Cortetsu shell, dotfiles, and system generations."""
from __future__ import annotations

import argparse
import fcntl
import json
import os
import re
import shutil
import subprocess
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

import dotfiles


class GenerationGCError(RuntimeError):
    pass


@dataclass(frozen=True)
class LayerPlan:
    name: str
    root: Path
    generations: tuple[Path, ...]
    protected: frozenset[Path]
    invalid: tuple[str, ...]
    sizes: dict[Path, int]

    @property
    def deletions(self) -> tuple[Path, ...]:
        return tuple(path for path in self.generations if path not in self.protected)

    @property
    def total_size(self) -> int:
        return sum(self.sizes.values())

    @property
    def reclaim_size(self) -> int:
        return sum(self.sizes[path] for path in self.deletions)


@dataclass(frozen=True)
class GCPlan:
    layers: dict[str, LayerPlan]
    keep: int
    pins: dict[str, tuple[str, ...]]
    symlinks: dict[str, str]


_PIN_NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")


def data_root() -> Path:
    return Path(os.environ.get("CORTETSU_DATA_ROOT", Path.home() / ".local/share/cortetsu")).expanduser()


def runtime_root() -> Path:
    return Path(os.environ.get("CORTETSU_RUNTIME_ROOT", Path.home() / ".config/quickshell/cortetsu")).expanduser()


def _real(path: Path) -> Path:
    return path.resolve(strict=False)


def _under(path: Path, root: Path) -> bool:
    try:
        _real(path).relative_to(_real(root))
    except ValueError:
        return False
    return True


def _generation_target(link: Path, root: Path, label: str) -> Path:
    if not link.is_symlink():
        raise GenerationGCError(f"{label} no es un symlink: {link}")
    try:
        target = link.resolve(strict=True)
    except OSError as exc:
        raise GenerationGCError(f"{label} apunta a una ruta inexistente: {link}") from exc
    root = _real(root)
    if target == root or target.parent != root or not target.is_dir() or not _under(target, root):
        raise GenerationGCError(f"{label} apunta fuera del root de generaciones: {target}")
    if target.is_symlink():
        raise GenerationGCError(f"{label} resuelve a un symlink no permitido: {target}")
    return target


def _direct_generations(root: Path, label: str) -> tuple[Path, ...]:
    root.mkdir(parents=True, exist_ok=True)
    result: list[Path] = []
    invalid: list[str] = []
    for child in sorted(root.iterdir(), key=lambda path: path.name, reverse=True):
        if child.is_symlink() or not child.is_dir() or child.name.startswith("."):
            invalid.append(str(child))
            continue
        if child.parent != root or _real(child) != child:
            invalid.append(str(child))
            continue
        result.append(child)
    if invalid:
        raise GenerationGCError(f"entradas inválidas en {label}: {', '.join(invalid)}")
    return tuple(result)


def _directory_size(path: Path) -> int:
    total = 0
    for base, dirs, files in os.walk(path, topdown=True, followlinks=False):
        dirs[:] = [name for name in dirs if not (Path(base) / name).is_symlink()]
        for name in files:
            entry = Path(base) / name
            try:
                if not entry.is_symlink():
                    # st_blocks reports allocated filesystem space, which is
                    # the number the operator can actually reclaim. The
                    # fallback keeps the planner portable to filesystems
                    # without st_blocks.
                    stat = entry.stat()
                    total += getattr(stat, "st_blocks", 0) * 512 or stat.st_size
            except OSError as exc:
                raise GenerationGCError(f"no se pudo medir {entry}: {exc}") from exc
    return total


def _validate_shell(path: Path) -> None:
    for required in ("shell.qml", "BUILD_ID", "BUILD.json"):
        if not (path / required).is_file():
            raise GenerationGCError(f"shell inválido, falta {required}: {path}")
    try:
        payload = json.loads((path / "BUILD.json").read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GenerationGCError(f"BUILD.json inválido: {path}: {exc}") from exc
    if payload.get("schema") != 1:
        raise GenerationGCError(f"schema shell no soportado: {path}")


def _validate_dotfiles(path: Path) -> None:
    try:
        dotfiles.validate_generation(path)
    except Exception as exc:
        raise GenerationGCError(f"MANIFEST.json inválido: {path}: {exc}") from exc


def _load_system(path: Path, shell_root: Path, dots_root: Path) -> dict:
    metadata = path / "SYSTEM.json"
    try:
        payload = json.loads(metadata.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise GenerationGCError(f"SYSTEM.json inválido: {path}: {exc}") from exc
    if payload.get("schema") != 1:
        raise GenerationGCError(f"schema de sistema no soportado: {path}")
    refs = (("shellGeneration", shell_root), ("dotfilesGeneration", dots_root))
    for key, root in refs:
        value = payload.get(key)
        if not isinstance(value, str) or not Path(value).is_absolute():
            raise GenerationGCError(f"{metadata} contiene {key} no absoluto")
        target = Path(value).resolve(strict=True)
        if target.parent != _real(root) or target.is_symlink() or not target.is_dir():
            raise GenerationGCError(f"{metadata} contiene {key} fuera de su root: {value}")
    return payload


def _pins(root: Path, layers: tuple[str, ...]) -> dict[str, tuple[str, ...]]:
    pins_root = root / "pins"
    result: dict[str, tuple[str, ...]] = {}
    for layer in layers:
        path = pins_root / f"{layer}.txt"
        names: list[str] = []
        if path.exists():
            if path.is_symlink() or not path.is_file():
                raise GenerationGCError(f"pin manifest inválido: {path}")
            for line_number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                value = raw.split("#", 1)[0].strip()
                if not value:
                    continue
                if not _PIN_NAME.fullmatch(value):
                    raise GenerationGCError(f"pin inválido en {path}:{line_number}: {value!r}")
                if value not in names:
                    names.append(value)
        result[layer] = tuple(names)
    return result


def _select_additional(generations: tuple[Path, ...], protected: set[Path], keep: int) -> None:
    for generation in generations:
        if generation not in protected and len(protected) >= keep:
            break
        protected.add(generation)


def _layer(
    name: str,
    root: Path,
    current: Path,
    previous: Path,
    extra: set[Path],
    pins: tuple[str, ...],
) -> LayerPlan:
    generations = _direct_generations(root, name)
    by_name = {path.name: path for path in generations}
    protected = {current, previous, *extra}
    for pin in pins:
        if pin not in by_name:
            raise GenerationGCError(f"pin {name}/{pin} no existe en {root}")
        protected.add(by_name[pin])
    unknown = protected.difference(generations)
    if unknown:
        raise GenerationGCError(f"referencia {name} no existe: {', '.join(map(str, unknown))}")
    invalid: list[str] = []
    for path in protected:
        try:
            if name == "shell":
                _validate_shell(path)
            elif name == "dotfiles":
                _validate_dotfiles(path)
        except GenerationGCError as exc:
            invalid.append(str(exc))
    if invalid:
        raise GenerationGCError("generaciones protegidas inválidas: " + "; ".join(invalid))
    sizes = {path: _directory_size(path) for path in generations}
    return LayerPlan(name, root, generations, frozenset(protected), tuple(invalid), sizes)


def build_plan(keep: int = 5) -> GCPlan:
    if keep < 0:
        raise GenerationGCError("--keep no puede ser negativo")
    data = _real(data_root())
    shell_root = data / "builds"
    dots_root = data / "dotfiles/builds"
    system_root = data / "system/builds"
    links = {
        "shell_current": runtime_root() / "current",
        "shell_previous": runtime_root() / "previous",
        "dotfiles_current": data / "dotfiles/current",
        "dotfiles_previous": data / "dotfiles/previous",
        "system_current": data / "system/current",
        "system_previous": data / "system/previous",
    }
    shell_current = _generation_target(links["shell_current"], shell_root, "shell current")
    shell_previous = _generation_target(links["shell_previous"], shell_root, "shell previous")
    dots_current = _generation_target(links["dotfiles_current"], dots_root, "dotfiles current")
    dots_previous = _generation_target(links["dotfiles_previous"], dots_root, "dotfiles previous")
    system_current = _generation_target(links["system_current"], system_root, "system current")
    system_previous = _generation_target(links["system_previous"], system_root, "system previous")

    system_generations = _direct_generations(system_root, "system")
    system_by_name = {path.name: path for path in system_generations}
    system_protected = {system_current, system_previous}
    _select_additional(system_generations, system_protected, len(system_protected) + keep)
    pin_values = _pins(data, ("shell", "dotfiles", "system"))
    for pin in pin_values["system"]:
        if pin not in system_by_name:
            raise GenerationGCError(f"pin system/{pin} no existe en {system_root}")
        system_protected.add(system_by_name[pin])
    system_refs: set[Path] = set()
    dots_refs: set[Path] = set()
    for generation in system_protected:
        payload = _load_system(generation, shell_root, dots_root)
        shell_ref = Path(payload["shellGeneration"]).resolve(strict=True)
        dots_ref = Path(payload["dotfilesGeneration"]).resolve(strict=True)
        if shell_ref.parent != _real(shell_root) or dots_ref.parent != _real(dots_root):
            raise GenerationGCError(f"SYSTEM.json retenido apunta fuera de los roots: {generation}")
        system_refs.add(shell_ref)
        dots_refs.add(dots_ref)

    current_payload = _load_system(system_current, shell_root, dots_root)
    if Path(current_payload["shellGeneration"]).resolve(strict=True) != shell_current:
        raise GenerationGCError("drift: shell current no coincide con system/current")
    if Path(current_payload["dotfilesGeneration"]).resolve(strict=True) != dots_current:
        raise GenerationGCError("drift: dotfiles current no coincide con system/current")

    layers = {
        "system": _layer("system", system_root, system_current, system_previous, system_protected.difference({system_current, system_previous}), pin_values["system"]),
        "shell": _layer("shell", shell_root, shell_current, shell_previous, system_refs, pin_values["shell"]),
        "dotfiles": _layer("dotfiles", dots_root, dots_current, dots_previous, dots_refs, pin_values["dotfiles"]),
    }
    symlinks = {name: str(_real(path)) for name, path in links.items()}
    return GCPlan(layers, keep, pin_values, symlinks)


def _human_bytes(value: int) -> str:
    units = ("B", "KiB", "MiB", "GiB")
    amount = float(value)
    for unit in units:
        if amount < 1024 or unit == units[-1]:
            return f"{amount:.2f} {unit}"
        amount /= 1024
    return f"{value} B"


def render(plan: GCPlan, dry_run: bool) -> str:
    lines = ["Cortetsu generation GC", f"MODE={'DRY-RUN' if dry_run else 'APPLY'}", f"KEEP_ADDITIONAL={plan.keep}"]
    for name in ("system", "shell", "dotfiles"):
        layer = plan.layers[name]
        lines += [
            f"\n{name.upper()}:",
            f"  generations={len(layer.generations)}",
            f"  protected={len(layer.protected)}",
            f"  delete={len(layer.deletions)}",
            f"  total_size={_human_bytes(layer.total_size)}",
            f"  estimated_reclaim={_human_bytes(layer.reclaim_size)}",
            "  PROTECTED " + ", ".join(sorted(path.name for path in layer.protected)),
            f"  WOULD_DELETE count={len(layer.deletions)}",
            "  WOULD_KEEP " + (", ".join(sorted(path.name for path in layer.protected)) or "none"),
        ]
    lines.append("\nINVALID: none")
    return "\n".join(lines)


def _metadata_snapshot(plan: GCPlan, repo: Path, dry_run_output: str) -> Path:
    data = _real(data_root())
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S-%fZ")
    backup = data / "gc-backups" / stamp
    backup.mkdir(parents=True, exist_ok=False)
    git_revision = "unknown"
    try:
        git_revision = subprocess.check_output(["git", "-C", str(repo), "rev-parse", "HEAD"], text=True).strip()
    except (OSError, subprocess.CalledProcessError):
        pass
    (backup / "dry-run.txt").write_text(dry_run_output + "\n", encoding="utf-8")
    (backup / "plan.json").write_text(json.dumps({
        "schema": 1,
        "createdAt": datetime.now(timezone.utc).isoformat(),
        "repositoryRevision": git_revision,
        "keepAdditional": plan.keep,
        "delete": {name: [str(path) for path in layer.deletions] for name, layer in plan.layers.items()},
        "protected": {name: [str(path) for path in layer.protected] for name, layer in plan.layers.items()},
        "symlinks": plan.symlinks,
    }, indent=2) + "\n", encoding="utf-8")
    (backup / "symlinks.json").write_text(json.dumps(plan.symlinks, indent=2) + "\n", encoding="utf-8")
    for name, layer in plan.layers.items():
        for path in layer.protected:
            target = backup / "metadata" / name / path.name
            target.mkdir(parents=True, exist_ok=True)
            for filename in ("BUILD_ID", "BUILD.json", "MANIFEST.json", "SYSTEM.json"):
                source = path / filename
                if source.is_file():
                    shutil.copy2(source, target / filename)
    return backup


def _safe_delete(path: Path, root: Path) -> None:
    root = _real(root)
    if path.parent != root or path == root or path.is_symlink() or _real(path) != path or not _under(path, root):
        raise GenerationGCError(f"target de borrado inseguro: {path}")
    if not path.is_dir():
        raise GenerationGCError(f"target de borrado no es directorio: {path}")
    shutil.rmtree(path)


def apply(plan: GCPlan) -> None:
    for name in ("system", "dotfiles", "shell"):
        layer = plan.layers[name]
        for path in layer.deletions:
            _safe_delete(path, layer.root)
    build_plan(plan.keep)


def run(repo: Path, keep: int = 5, dry_run: bool = False) -> int:
    data = _real(data_root())
    lock_path = data / "gc.lock"
    if dry_run:
        plan = build_plan(keep)
        print(render(plan, True))
        return 0
    data.mkdir(parents=True, exist_ok=True)
    with lock_path.open("w", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        plan = build_plan(keep)
        output = render(plan, False)
        backup = _metadata_snapshot(plan, repo, output)
        apply(plan)
        print(output)
        print(f"BACKUP_METADATA {backup}")
        print("GC_APPLIED verified=plan-and-links")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Cortetsu coordinated generation garbage collection")
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--keep", type=int, default=5)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()
    try:
        return run(args.repo.resolve(), args.keep, args.dry_run)
    except (GenerationGCError, OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"ERROR: {exc}", file=os.sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
