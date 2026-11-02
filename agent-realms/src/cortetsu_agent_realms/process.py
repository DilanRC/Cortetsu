from __future__ import annotations

import json
import fcntl
import os
import re
import shutil
import signal
import stat
import subprocess
import threading
import time
from contextlib import contextmanager
from functools import wraps
from pathlib import Path
from typing import Any, Callable, TypeVar

from .paths import RealmError, RealmPaths, paths_for


META_NAME = "session.json"
_lifecycle_registry_guard = threading.Lock()
_lifecycle_locks: dict[str, threading.RLock] = {}
_lifecycle_local = threading.local()
F = TypeVar("F", bound=Callable[..., Any])


@contextmanager
def lifecycle_lock(paths: RealmPaths):
    control = paths.control
    control.mkdir(mode=0o700, parents=True, exist_ok=True)
    control.chmod(0o700)
    key = str(control.resolve())
    with _lifecycle_registry_guard:
        lock = _lifecycle_locks.setdefault(key, threading.RLock())
    lock.acquire()
    held = getattr(_lifecycle_local, "held", None)
    if held is None:
        held = {}
        _lifecycle_local.held = held
    current = held.get(key)
    try:
        if current is None:
            lock_path = control / ".lifecycle.lock"
            flags = os.O_CREAT | os.O_RDWR | os.O_CLOEXEC | getattr(os, "O_NOFOLLOW", 0)
            fd = os.open(lock_path, flags, 0o600)
            os.fchmod(fd, 0o600)
            fcntl.flock(fd, fcntl.LOCK_EX)
            held[key] = [fd, 1]
        else:
            current[1] += 1
        try:
            yield
        finally:
            entry = held[key]
            entry[1] -= 1
            if entry[1] == 0:
                del held[key]
                fcntl.flock(entry[0], fcntl.LOCK_UN)
                os.close(entry[0])
    finally:
        lock.release()


def lifecycle_serialized(function: F) -> F:
    @wraps(function)
    def wrapped(name: str, *args: Any, **kwargs: Any) -> Any:
        paths = paths_for(name)
        with lifecycle_lock(paths):
            return function(name, *args, **kwargs)
    return wrapped  # type: ignore[return-value]


def meta_path(paths: RealmPaths) -> Path:
    return paths.control / META_NAME


def load_meta(paths: RealmPaths) -> dict[str, Any]:
    try:
        data = json.loads(meta_path(paths).read_text())
    except FileNotFoundError as exc:
        if (paths.state / META_NAME).exists():
            raise RealmError(f"la sesión {paths.name!r} usa el formato anterior a control/; "
                             "detenla con la versión previa o revisa sus scopes antes de borrar "
                             f"{paths.state / META_NAME}") from exc
        raise RealmError(f"no existe la sesión {paths.name!r}") from exc
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise RealmError(f"metadatos dañados para {paths.name!r}: {exc}") from exc
    if not isinstance(data, dict):
        raise RealmError(f"metadatos dañados para {paths.name!r}: se esperaba un objeto JSON")
    if data.get("name") != paths.name or data.get("schema") != 1:
        raise RealmError("los metadatos no corresponden a esta sesión")
    return data


REPORT_NAME = "realm-report.json"
_CONTROL_CHARS = re.compile(r"[\x00-\x08\x0b-\x1f\x7f-\x9f]")


def read_untrusted(path: Path, limit: int = 256 * 1024) -> str:
    """Read a file that realm processes can replace: no symlinks, FIFOs or devices.

    Returns at most the last `limit` bytes; terminal control characters are stripped.
    """
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK | os.O_CLOEXEC)
    try:
        info = os.fstat(fd)
        if not stat.S_ISREG(info.st_mode):
            raise OSError(f"{path.name} no es un archivo regular")
        if info.st_size > limit:
            os.lseek(fd, info.st_size - limit, os.SEEK_SET)
        data = os.read(fd, limit)
    finally:
        os.close(fd)
    return _CONTROL_CHARS.sub("", data.decode(errors="replace"))
_SIGNATURE_RE = re.compile(r"^[A-Za-z0-9_]{1,128}$")
_DISPLAY_RE = re.compile(r"^wayland-[0-9]{1,4}$")


SUPERVISOR_MODULE_ARGV = ("-m", "cortetsu_agent_realms.supervisor")


def supervisor_present(unit: str, proc_root: Path = Path("/proc")) -> bool:
    # Advisory only: a realm process could fake this argv, but it cannot hide a
    # real supervisor, so a False answer is trustworthy.
    for entry in proc_root.iterdir():
        if not entry.name.isdigit():
            continue
        try:
            if unit not in (entry / "cgroup").read_text():
                continue
            argv = (entry / "cmdline").read_bytes().split(b"\0")
        except OSError:
            continue
        # bwrap wrappers carry the same words in their argv; match the interpreter itself.
        if argv[0].endswith(b"python") and argv[1:3] == [arg.encode() for arg in SUPERVISOR_MODULE_ARGV]:
            return True
    return False


def load_realm_report(paths: RealmPaths) -> dict[str, Any] | None:
    """Endpoints published by the in-realm supervisor, validated.

    Any realm process can rewrite this file, so only names that resolve inside
    the realm's private runtime are accepted; PIDs and scope units are never
    taken from it.
    """
    try:
        data = json.loads(read_untrusted(paths.state / REPORT_NAME, 64 * 1024))
    except (OSError, UnicodeError, ValueError):
        return None
    if not isinstance(data, dict) or data.get("name") != paths.name:
        return None
    report: dict[str, Any] = {}
    if isinstance(data.get("state"), str) and data["state"] in {"starting", "stopped", "crashed", "failed"}:
        report["state"] = data["state"]
    if isinstance(data.get("error"), str):
        report["error"] = _CONTROL_CHARS.sub("", data["error"])[:2000]
    sig, display = data.get("signature"), data.get("wayland_display")
    if isinstance(sig, str) and isinstance(display, str) and _SIGNATURE_RE.fullmatch(sig) \
            and _DISPLAY_RE.fullmatch(display):
        report["signature"] = sig
        report["wayland_display"] = display
        bus = f"unix:path={paths.internal_runtime}/bus"
        if data.get("dbus_session_bus_address") == bus:
            report["dbus_session_bus_address"] = bus
    return report


def save_meta(paths: RealmPaths, data: dict[str, Any]) -> None:
    target = meta_path(paths)
    tmp = target.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    tmp.chmod(0o600)
    os.replace(tmp, target)


def proc_start_time(pid: int) -> int | None:
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
        fields = raw[raw.rfind(")") + 2 :].split()
        return int(fields[19])  # stat field 22, after pid/comm
    except (OSError, ValueError, IndexError):
        return None


def same_process(pid: int, start_time: int | None) -> bool:
    if (isinstance(pid, bool) or not isinstance(pid, int) or pid <= 1
            or isinstance(start_time, bool) or not isinstance(start_time, int)):
        return False
    return proc_start_time(pid) == start_time


def process_alive(meta: dict[str, Any]) -> bool:
    unit = meta.get("systemd_scope_unit")
    name = meta.get("name")
    if isinstance(unit, str) and isinstance(name, str) and _valid_scope_unit(name, unit):
        systemctl = shutil.which("systemctl", path="/usr/bin:/bin")
        if systemctl:
            try:
                result = subprocess.run([systemctl, "--user", "is-active", "--quiet", unit],
                                        capture_output=True, text=True, timeout=3)
                return result.returncode == 0
            except (OSError, subprocess.SubprocessError):
                pass
    pid = meta.get("leader_pid")
    start_time = meta.get("leader_start_time")
    if isinstance(pid, bool) or not isinstance(pid, int):
        return False
    if pid <= 1 or not same_process(pid, start_time):
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def _valid_scope_unit(name: str, unit: str) -> bool:
    return re.fullmatch(rf"agent-realm-{re.escape(name)}-[0-9a-f]{{10}}\.scope", unit) is not None


def control_scope(name: str, unit: str, action: str) -> None:
    if not _valid_scope_unit(name, unit):
        raise RealmError(f"unidad systemd fuera del patrón del realm {name!r}")
    if action not in {"stop", "freeze", "thaw"}:
        raise RealmError(f"acción systemd no admitida: {action}")
    systemctl = shutil.which("systemctl", path="/usr/bin:/bin")
    if not systemctl:
        raise RealmError("systemctl no está disponible para administrar el scope del realm")
    try:
        loaded = subprocess.run([systemctl, "--user", "show", unit, "--property=LoadState", "--value"],
                                capture_output=True, text=True, timeout=5)
        if loaded.returncode == 0 and loaded.stdout.strip() == "not-found":
            return
        if loaded.returncode != 0:
            detail = loaded.stderr.strip() or loaded.stdout.strip() or f"código {loaded.returncode}"
            raise RealmError(f"no se pudo inspeccionar {unit}: {detail}")
        result = subprocess.run([systemctl, "--user", action, unit],
                                capture_output=True, text=True, timeout=15)
    except RealmError:
        raise
    except (OSError, subprocess.SubprocessError) as exc:
        raise RealmError(f"systemctl {action} {unit} falló: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"código {result.returncode}"
        raise RealmError(f"systemctl {action} {unit} falló: {detail}")


def scope_freezer_state(name: str, unit: str) -> str:
    if not _valid_scope_unit(name, unit):
        raise RealmError(f"unidad systemd fuera del patrón del realm {name!r}")
    systemctl = shutil.which("systemctl", path="/usr/bin:/bin")
    if not systemctl:
        raise RealmError("systemctl no está disponible para consultar el estado de congelación")
    try:
        result = subprocess.run([systemctl, "--user", "show", unit,
                                 "--property=FreezerState", "--value"],
                                capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RealmError(f"no se pudo consultar FreezerState de {unit}: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"código {result.returncode}"
        raise RealmError(f"no se pudo consultar FreezerState de {unit}: {detail}")
    state = result.stdout.strip()
    if state not in {"running", "frozen"}:
        raise RealmError(f"FreezerState no es estable para {unit}: {state or 'vacío'}")
    return state


def signal_group(pid: int, start_time: int | None, sig: int) -> bool:
    if not same_process(pid, start_time):
        return False
    try:
        os.killpg(pid, sig)
        return True
    except ProcessLookupError:
        return False


def stop_group(pid: int, start_time: int | None, timeout: float = 4.0) -> None:
    if not signal_group(pid, start_time, signal.SIGTERM):
        return
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if not same_process(pid, start_time):
            return
        time.sleep(0.05)
    signal_group(pid, start_time, signal.SIGKILL)


def cleanup_groups(paths: RealmPaths, *, allow_corrupt_session_meta: bool = False) -> None:
    app_dir = paths.control / "apps"
    records = list(app_dir.glob("*.json")) if app_dir.is_dir() else []
    units = set(_realm_scope_units(paths.name))
    old_processes: list[tuple[int, int | None]] = []
    unresolved_apps: list[str] = []
    unresolved_session_meta = False
    for record in records:
        try:
            data = json.loads(record.read_text())
        except (OSError, ValueError, json.JSONDecodeError):
            unresolved_apps.append(record.name)
            continue
        if not isinstance(data, dict):
            unresolved_apps.append(record.name)
            continue
        unit = data.get("systemd_scope_unit")
        if isinstance(unit, str):
            if _valid_scope_unit(paths.name, unit):
                units.add(unit)
            else:
                identity = _recorded_process_identity(data, "pid", "start_time")
                if identity:
                    old_processes.append(identity)
                else:
                    unresolved_apps.append(record.name)
        else:
            identity = _recorded_process_identity(data, "pid", "start_time")
            if identity:
                old_processes.append(identity)
            else:
                unresolved_apps.append(record.name)
    try:
        meta = load_meta(paths)
        unit = meta.get("systemd_scope_unit")
        if isinstance(unit, str):
            if _valid_scope_unit(paths.name, unit):
                units.add(unit)
            else:
                identity = _recorded_process_identity(meta, "leader_pid", "leader_start_time")
                if identity:
                    old_processes.append(identity)
                else:
                    unresolved_session_meta = True
        else:
            identity = _recorded_process_identity(meta, "leader_pid", "leader_start_time")
            if identity:
                old_processes.append(identity)
            elif "leader_pid" in meta or "leader_start_time" in meta:
                unresolved_session_meta = True
    except RealmError:
        if meta_path(paths).exists() and not allow_corrupt_session_meta:
            raise
    for unit in sorted(units):
        control_scope(paths.name, unit, "stop")
        if process_alive({"name": paths.name, "systemd_scope_unit": unit}):
            raise RealmError(f"el scope del realm sigue activo tras stop: {unit}")
    for pid, start_time in old_processes:
        stop_group(pid, start_time, timeout=1.2)
        if same_process(pid, start_time):
            raise RealmError(f"el grupo de procesos {pid} continúa vivo tras su parada")
    if unresolved_apps:
        raise RealmError("registros corruptos sin unidad o identidad de proceso segura: " +
                         ", ".join(sorted(set(unresolved_apps))))
    if unresolved_session_meta and not allow_corrupt_session_meta:
        raise RealmError("metadatos de sesión sin unidad o identidad de proceso segura")
    for record in records:
        record.unlink(missing_ok=True)


def _recorded_process_identity(data: dict[str, Any], pid_key: str,
                               start_time_key: str) -> tuple[int, int] | None:
    pid, start_time = data.get(pid_key), data.get(start_time_key)
    if (isinstance(pid, bool) or not isinstance(pid, int)
            or isinstance(start_time, bool) or not isinstance(start_time, int)):
        return None
    if pid <= 1 or start_time <= 0:
        return None
    return pid, start_time


def _realm_scope_units(name: str) -> set[str]:
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9_.-]{0,47}", name):
        raise RealmError("nombre de realm inválido al enumerar scopes")
    systemctl = shutil.which("systemctl", path="/usr/bin:/bin")
    if not systemctl:
        raise RealmError("systemctl no está disponible para enumerar scopes del realm")
    pattern = f"agent-realm-{name}-*.scope"
    try:
        result = subprocess.run([systemctl, "--user", "list-units", "--all", "--type=scope",
                                 "--full", "--plain", "--no-legend", "--no-pager", pattern],
                                capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError) as exc:
        raise RealmError(f"no se pudieron enumerar scopes de {name!r}: {exc}") from exc
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"código {result.returncode}"
        raise RealmError(f"no se pudieron enumerar scopes de {name!r}: {detail}")
    units = set()
    for line in result.stdout.splitlines():
        fields = line.split()
        if fields and _valid_scope_unit(name, fields[0]):
            units.add(fields[0])
    return units


def app_groups(paths: RealmPaths) -> list[dict[str, Any]]:
    result = []
    for record in (paths.control / "apps").glob("*.json"):
        try:
            data = json.loads(record.read_text())
        except (OSError, UnicodeError, json.JSONDecodeError) as exc:
            raise RealmError(f"registro de app ilegible; se conserva para recover: {record.name}") from exc
        if not isinstance(data, dict):
            raise RealmError(f"registro de app sin objeto JSON; se conserva para recover: {record.name}")
        unit = data.get("systemd_scope_unit")
        if isinstance(unit, str) and _valid_scope_unit(paths.name, unit):
            if process_alive({"name": paths.name, "systemd_scope_unit": unit}):
                result.append(data)
            else:
                record.unlink(missing_ok=True)
        else:
            identity = _recorded_process_identity(data, "pid", "start_time")
            if not identity:
                raise RealmError(f"registro de app sin unidad o identidad segura; se conserva: {record.name}")
            if same_process(*identity):
                result.append(data)
            else:
                record.unlink(missing_ok=True)
    return result
