from __future__ import annotations

import os
import re
import hashlib
import stat
from dataclasses import dataclass
from pathlib import Path


NAME_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,47}$")


class RealmError(RuntimeError):
    pass


@dataclass(frozen=True)
class RealmPaths:
    name: str
    state: Path
    home: Path
    runtime: Path
    config: Path
    log: Path
    compositor_log: Path
    # Host-owned records (session, lock, apps, captures); never mounted in the realm.
    control: Path

    @property
    def internal_runtime(self) -> str:
        return str(self.runtime)

    @property
    def parent_runtime(self) -> Path:
        return self.runtime.with_name("ap" + self.runtime.name[2:])

    @property
    def parent_internal_runtime(self) -> str:
        return str(self.parent_runtime)

    @property
    def parent_log(self) -> Path:
        return self.state / "weston.log"


def validate_name(name: str) -> str:
    if not NAME_RE.fullmatch(name):
        raise RealmError("el nombre debe usar 1–48 letras, números, punto, guion o guion bajo")
    return name


def state_root() -> Path:
    base = Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
    return base / "cortetsu-agent-realms"


def data_root() -> Path:
    base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local/share"))
    return base / "cortetsu-agent-realms"


def host_runtime_root() -> Path:
    value = os.environ.get("XDG_RUNTIME_DIR")
    if not value:
        raise RealmError("XDG_RUNTIME_DIR no está definido; no se usará el runtime del anfitrión")
    root = Path(value)
    try:
        st = root.stat()
    except OSError as exc:
        raise RealmError(f"XDG_RUNTIME_DIR no está disponible: {exc}") from exc
    if st.st_uid != os.getuid() or st.st_mode & 0o077:
        raise RealmError("XDG_RUNTIME_DIR debe pertenecer al usuario y tener permisos privados")
    return root


def _runtime_path(name: str) -> Path:
    # Kept short on purpose: Hyprland's event socket lives at
    # <runtime>/hypr/<signature>/.socket2.sock and sockaddr_un holds 107 bytes.
    # With "/tmp/ar-<uid>-..." that path reached 108 and Quickshell could not
    # subscribe to Hyprland events. The uid stays in the digest and
    # _ensure_private_runtime rejects a directory owned by someone else.
    digest = hashlib.blake2s(f"{os.getuid()}:{name}".encode(), digest_size=6).hexdigest()
    return Path("/tmp") / f"ar{digest}"


def _ensure_private_runtime(path: Path) -> None:
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    except OSError as exc:
        raise RealmError(f"no se pudo crear el runtime privado {path}: {exc}") from exc
    try:
        info = path.lstat()
    except OSError as exc:
        raise RealmError(f"no se pudo inspeccionar el runtime privado {path}: {exc}") from exc
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise RealmError(f"runtime privado inseguro; se requiere directorio propio, no symlink: {path}")
    try:
        path.chmod(0o700)
    except OSError as exc:
        raise RealmError(f"no se pudieron ajustar permisos del runtime privado {path}: {exc}") from exc


def paths_for(name: str, *, create: bool = False) -> RealmPaths:
    validate_name(name)
    root = state_root()
    control = root.parent / "cortetsu-agent-realms-control" / name
    p = RealmPaths(
        name=name,
        state=root / name,
        home=data_root() / name / "home",
        runtime=_runtime_path(name),
        config=control / "hyprland.conf",
        log=control / "supervisor.log",
        compositor_log=root / name / "hyprland.log",
        control=control,
    )
    if create:
        for folder in (p.state, p.control, p.home, p.home / ".config", p.home / ".cache",
                       p.home / ".local/share", p.home / ".local/state"):
            folder.mkdir(mode=0o700, parents=True, exist_ok=True)
            try:
                folder.chmod(0o700)
            except OSError:
                pass
        _ensure_private_runtime(p.runtime)
        _ensure_private_runtime(p.parent_runtime)
    return p


def repo_root() -> Path:
    return Path(__file__).resolve().parents[2]
