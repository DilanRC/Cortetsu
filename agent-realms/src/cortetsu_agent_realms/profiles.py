"""Client profiles: which realm an MCP client drives and with which capabilities.

The binding lives in a host file the user writes; the MCP server receives only a
profile name in its launch arguments. Tools never take a realm name, so a model
cannot point actions at another realm or at the host compositor.
"""
from __future__ import annotations

import json
import os
import stat
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from .auth import Capability
from .paths import RealmError, validate_name

SCHEMA = 1
LIFECYCLES = {"persistent", "ephemeral"}
MAX_PROFILE_BYTES = 64 * 1024


@dataclass(frozen=True)
class Profile:
    name: str
    realm: str
    capabilities: frozenset[Capability]
    lifecycle: str = "persistent"
    autostart: bool = True
    start: dict[str, Any] = field(default_factory=dict)

    def allows(self, capability: Capability) -> bool:
        return capability in self.capabilities

    def describe(self) -> dict[str, Any]:
        return {"profile": self.name, "realm": self.realm, "lifecycle": self.lifecycle,
                "autostart": self.autostart, "capabilities": sorted(c.value for c in self.capabilities)}


def profiles_path() -> Path:
    base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    return base / "cortetsu-agent-realms" / "profiles.json"


_START_KEYS = {"width": int, "height": int, "lua": bool, "workspace": str, "readonly_workspace": bool,
               "memory_max": str, "cpu_quota": str, "tasks_max": int}


def _parse_profile(name: str, raw: Any) -> Profile:
    validate_name(name)
    if not isinstance(raw, dict):
        raise RealmError(f"perfil {name!r}: se esperaba un objeto")
    unknown = set(raw) - {"realm", "capabilities", "lifecycle", "autostart", "start"}
    if unknown:
        raise RealmError(f"perfil {name!r}: claves desconocidas {sorted(unknown)}")
    realm = raw.get("realm")
    if not isinstance(realm, str):
        raise RealmError(f"perfil {name!r}: falta realm")
    validate_name(realm)
    caps = raw.get("capabilities", ["observe"])
    if not isinstance(caps, list) or not all(isinstance(c, str) for c in caps):
        raise RealmError(f"perfil {name!r}: capabilities debe ser una lista")
    try:
        capabilities = Capability.parse(caps)
    except ValueError as exc:
        raise RealmError(f"perfil {name!r}: {exc}") from exc
    lifecycle = raw.get("lifecycle", "persistent")
    if lifecycle not in LIFECYCLES:
        raise RealmError(f"perfil {name!r}: lifecycle debe ser persistent o ephemeral")
    autostart = raw.get("autostart", True)
    if not isinstance(autostart, bool):
        raise RealmError(f"perfil {name!r}: autostart debe ser booleano")
    start = raw.get("start", {})
    if not isinstance(start, dict):
        raise RealmError(f"perfil {name!r}: start debe ser un objeto")
    for key, value in start.items():
        expected = _START_KEYS.get(key)
        if expected is None or type(value) is not expected:
            raise RealmError(f"perfil {name!r}: start.{key} no admitido o con tipo incorrecto")
    return Profile(name, realm, capabilities, lifecycle, autostart, dict(start))


def _read_private(path: Path) -> str:
    """Read the profile file only if the user owns it and nobody else can write it or its folder."""
    parent = path.parent.lstat() if path.parent.exists() else None
    if parent is None:
        raise RealmError(f"no existe {path}; crea un perfil con `agent-realm profile set`")
    if not stat.S_ISDIR(parent.st_mode) or parent.st_uid != os.getuid() or parent.st_mode & 0o022:
        raise RealmError(f"{path.parent} debe ser un directorio propio sin escritura de grupo u otros")
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    except FileNotFoundError as exc:
        raise RealmError(f"no existe {path}; crea un perfil con `agent-realm profile set`") from exc
    except OSError as exc:
        raise RealmError(f"no se pudo abrir {path} de forma segura (¿symlink?): {exc}") from exc
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o022:
            raise RealmError(f"{path} debe ser un archivo regular propio sin escritura de grupo u otros")
        if info.st_size > MAX_PROFILE_BYTES:
            raise RealmError(f"{path} supera {MAX_PROFILE_BYTES} bytes")
        return os.read(fd, MAX_PROFILE_BYTES).decode()
    finally:
        os.close(fd)


def load_all(path: Path | None = None) -> dict[str, Profile]:
    path = path or profiles_path()
    try:
        data = json.loads(_read_private(path))
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise RealmError(f"{path} no contiene JSON válido: {exc}") from exc
    if not isinstance(data, dict) or data.get("schema") != SCHEMA or not isinstance(data.get("profiles"), dict):
        raise RealmError(f"{path}: se esperaba {{\"schema\": {SCHEMA}, \"profiles\": {{...}}}}")
    profiles = {name: _parse_profile(name, raw) for name, raw in data["profiles"].items()}
    realms: dict[str, str] = {}
    for profile in profiles.values():
        if profile.realm in realms:
            raise RealmError(f"los perfiles {realms[profile.realm]!r} y {profile.name!r} comparten el realm "
                             f"{profile.realm!r}; cada cliente necesita su propio escritorio")
        realms[profile.realm] = profile.name
    return profiles


def load(name: str, path: Path | None = None) -> Profile:
    profiles = load_all(path)
    if name not in profiles:
        raise RealmError(f"no existe el perfil {name!r}; disponibles: {', '.join(sorted(profiles)) or 'ninguno'}")
    return profiles[name]


def _write(path: Path, data: dict[str, Any]) -> None:
    tmp = path.with_suffix(".json.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    with os.fdopen(fd, "w") as handle:
        handle.write(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")
    os.replace(tmp, path)


def save_profile(name: str, raw: dict[str, Any], path: Path | None = None) -> Profile:
    """Create or replace one profile, keeping the others; validates the whole file first."""
    path = path or profiles_path()
    profile = _parse_profile(name, raw)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        current = json.loads(_read_private(path))
    except RealmError:
        if path.exists() or path.is_symlink():
            raise
        current = {"schema": SCHEMA, "profiles": {}}
    current.setdefault("profiles", {})[name] = raw
    for other, other_raw in current["profiles"].items():
        if other != name and isinstance(other_raw, dict) and other_raw.get("realm") == profile.realm:
            raise RealmError(f"el realm {profile.realm!r} ya pertenece al perfil {other!r}")
    _write(path, current)
    return profile


def remove_profile(name: str, path: Path | None = None) -> bool:
    path = path or profiles_path()
    current = json.loads(_read_private(path))
    if name not in current.get("profiles", {}):
        return False
    del current["profiles"][name]
    _write(path, current)
    return True
