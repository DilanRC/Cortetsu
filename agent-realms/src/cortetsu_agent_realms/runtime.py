from __future__ import annotations

import json
import hashlib
import os
import re
import shlex
import shutil
import stat
import subprocess
import sys
import time
import uuid
from pathlib import Path
from typing import Any

from .paths import (RealmError, RealmPaths, data_root, host_runtime_root, paths_for,
                    repo_root, state_root, validate_name)
from .process import (
    app_groups,
    cleanup_groups,
    control_scope,
    load_meta,
    load_realm_report,
    read_untrusted,
    SUPERVISOR_MODULE_ARGV,
    REPORT_NAME,
    meta_path,
    lifecycle_lock,
    lifecycle_serialized,
    proc_start_time,
    process_alive,
    _realm_scope_units,
    scope_freezer_state,
    save_meta,
    _valid_scope_unit,
)


def _mkdir_private(path: Path) -> None:
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    path.chmod(0o700)


def _find_amd_render_node() -> str | None:
    for node in sorted(Path("/sys/class/drm").glob("renderD*/device/vendor")):
        try:
            if node.read_text().strip().lower() == "0x1002":
                name = node.parent.parent.name
                path = Path("/dev/dri") / name
                if path.exists():
                    return str(path)
        except OSError:
            continue
    return None


def _compositor_path(override: str | None = None) -> str:
    name = override or os.environ.get("CORTETSU_AGENT_REALMS_HYPRLAND", "Hyprland")
    path = str(Path(name).expanduser()) if "/" in name else shutil.which(
        name, path="/usr/local/bin:/usr/bin:/bin")
    if not path:
        raise RealmError(f"no se encuentra el ejecutable Hyprland {name!r}")
    return str(Path(path).resolve())


def _weston_path() -> str:
    name = os.environ.get("CORTETSU_AGENT_REALMS_WESTON", "weston")
    path = str(Path(name).expanduser()) if "/" in name else shutil.which(
        name, path="/usr/local/bin:/usr/bin:/bin")
    if not path:
        raise RealmError("no se encuentra Weston, requerido como padre Wayland headless")
    return str(Path(path).resolve())


def xdg_version_shim_binary() -> Path:
    root = repo_root()
    source = root / "src/xdg-version-shim.c"
    script = root / "scripts/build-xdg-version-shim.sh"
    pkg_config = shutil.which("pkg-config", path="/usr/bin:/bin")
    if not pkg_config:
        raise RealmError("pkg-config no está disponible para compilar el shim Wayland local")
    version = subprocess.run([pkg_config, "--modversion", "wayland-server"],
                             capture_output=True, text=True, timeout=5)
    if version.returncode != 0:
        raise RealmError("faltan headers o biblioteca wayland-server para el shim: " + version.stderr.strip())
    digest = hashlib.sha256(source.read_bytes() + script.read_bytes() + version.stdout.encode()).hexdigest()[:16]
    cache = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / "cortetsu-agent-realms"
    cache.mkdir(mode=0o700, parents=True, exist_ok=True)
    cache.chmod(0o700)
    target = cache / f"xdg-version-shim-{digest}.so"
    if target.is_file() and os.access(target, os.X_OK):
        return target
    result = subprocess.run(["/bin/bash", str(script), str(target)],
                            capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RealmError("no se pudo compilar el shim Weston; requiere wayland-server, pkg-config y cc: " +
                         result.stderr.strip())
    return target


def _validate_limits(memory_max: str, cpu_quota: str, tasks_max: int) -> None:
    import re
    if not re.fullmatch(r"[1-9][0-9]*(?:K|M|G|T)?", memory_max):
        raise RealmError("--memory-max usa una cantidad como 4G, 2048M o 900K")
    if not re.fullmatch(r"[1-9][0-9]{0,2}%", cpu_quota) or int(cpu_quota[:-1]) > 800:
        raise RealmError("--cpu-quota debe ser un porcentaje de 1% a 800%")
    if tasks_max < 32 or tasks_max > 8192:
        raise RealmError("--tasks-max debe estar entre 32 y 8192")


def _scope_command(name: str, command: list[str], *, memory_max: str = "6G",
                   cpu_quota: str = "200%", tasks_max: int = 512) -> tuple[list[str], str]:
    _validate_limits(memory_max, cpu_quota, tasks_max)
    systemd_run = shutil.which("systemd-run", path="/usr/bin:/bin")
    if not systemd_run:
        raise RealmError("systemd-run no está disponible; no se iniciará un realm sin límites de recursos")
    unit = f"agent-realm-{name}-{uuid.uuid4().hex[:10]}.scope"
    prefix = [systemd_run, "--user", "--scope", "--collect", "--quiet", f"--unit={unit}",
              f"--property=MemoryMax={memory_max}", f"--property=CPUQuota={cpu_quota}",
              f"--property=TasksMax={tasks_max}", "--"]
    return prefix + command, unit


def _manager_env() -> dict[str, str]:
    runtime = str(host_runtime_root())
    return {"PATH": "/usr/local/bin:/usr/bin:/bin", "LANG": os.environ.get("LANG", "C.UTF-8"),
            "XDG_RUNTIME_DIR": runtime, "DBUS_SESSION_BUS_ADDRESS": f"unix:path={runtime}/bus"}


def _runtime_env(paths: RealmPaths, *, wayland: str | None = None,
                 signature: str | None = None, bus: str | None = None) -> dict[str, str]:
    env = {
        "HOME": "/home/agent",
        "USER": os.environ.get("USER", "agent"),
        "LOGNAME": os.environ.get("USER", "agent"),
        "PATH": "/home/agent/.local/bin:/usr/local/bin:/usr/bin:/bin",
        "LANG": os.environ.get("LANG", "C.UTF-8"),
        "LC_ALL": os.environ.get("LC_ALL", os.environ.get("LANG", "C.UTF-8")),
        "XDG_CONFIG_HOME": "/home/agent/.config",
        "XDG_CACHE_HOME": "/home/agent/.cache",
        "XDG_DATA_HOME": "/home/agent/.local/share",
        "XDG_STATE_HOME": "/home/agent/.local/state",
        "XDG_DATA_DIRS": "/usr/local/share:/usr/share",
        "XDG_RUNTIME_DIR": paths.internal_runtime,
        "XDG_SESSION_TYPE": "wayland",
        "XDG_CURRENT_DESKTOP": "Hyprland",
        "XDG_SESSION_DESKTOP": "Hyprland",
        "HYPRLAND_NO_SD_VARS": "1",
        "HYPRLAND_NO_SD_NOTIFY": "1",
        "HYPRLAND_NO_RT": "1",
        # Absent unless `agent-realm simulate` runs the realm's private system bus.
        "DBUS_SYSTEM_BUS_ADDRESS": f"unix:path={paths.internal_runtime}/system_bus_socket",
        "QT_QPA_PLATFORM": "wayland",
        "QT_WAYLAND_DISABLE_WINDOWDECORATION": "1",
        "GDK_BACKEND": "wayland",
        "SDL_VIDEODRIVER": "wayland",
    }
    render = _find_amd_render_node()
    if render:
        env["AQ_DRM_DEVICES"] = render
        env["MESA_LOADER_DRIVER_OVERRIDE"] = "radeonsi"
    if wayland:
        env["WAYLAND_DISPLAY"] = wayland
    if signature:
        env["HYPRLAND_INSTANCE_SIGNATURE"] = signature
    if bus:
        env["DBUS_SESSION_BUS_ADDRESS"] = bus
    return env


def _bwrap_prefix(paths: RealmPaths, *, workspace: Path | None = None,
                  readonly_workspace: bool = False, die_with_parent: bool = True,
                  compositor: str | None = None, include_parent: bool = False,
                  version_shim: Path | None = None,
                  input_client: Path | None = None,
                  readonly_state: bool = True) -> list[str]:
    bwrap = shutil.which("bwrap")
    if not bwrap:
        raise RealmError("bubblewrap (bwrap) no está instalado")
    args = [bwrap, "--unshare-user", "--unshare-pid", "--unshare-uts", "--new-session", "--clearenv"]
    if die_with_parent:
        args.append("--die-with-parent")
    args += ["--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
             "--symlink", "usr/bin", "/sbin", "--symlink", "usr/lib", "/lib",
             "--symlink", "usr/lib", "/lib64", "--ro-bind", "/etc", "/etc",
             "--proc", "/proc", "--dev", "/dev", "--tmpfs", "/tmp"]
    if Path("/sys").exists():
        args += ["--ro-bind", "/sys", "/sys"]
    if Path("/opt").exists():
        args += ["--ro-bind", "/opt", "/opt"]
    state_bind = "--ro-bind" if readonly_state else "--bind"
    args += ["--dir", "/home", "--dir", "/home/agent", "--bind", str(paths.home), "/home/agent",
             "--dir", "/var", "--dir", "/var/lib", state_bind, str(paths.state), "/var/lib/agent-realm",
             "--symlink", "../run", "/var/run",
             "--dir", paths.internal_runtime,
             "--bind", str(paths.runtime), paths.internal_runtime]
    if include_parent:
        args += ["--dir", paths.parent_internal_runtime,
                 "--bind", str(paths.parent_runtime), paths.parent_internal_runtime]
    if version_shim:
        args += ["--ro-bind", str(version_shim), "/tmp/agent-realm-xdg-version-shim.so"]
    if input_client:
        args += ["--ro-bind", str(input_client), "/tmp/agent-realm-input-client"]
    render = _find_amd_render_node()
    if render:
        args += ["--dir", "/dev/dri", "--dev-bind", render, render]
    if workspace:
        workspace = workspace.expanduser().resolve(strict=True)
        args += ["--dir", "/workspace", "--ro-bind" if readonly_workspace else "--bind",
                 str(workspace), "/workspace"]
    if compositor:
        comp = Path(compositor).resolve()
        if not (str(comp).startswith("/usr/") or str(comp).startswith("/bin/")):
            args += ["--ro-bind", str(comp), "/tmp/agent-realm-Hyprland"]
    env = _runtime_env(paths)
    for key, value in env.items():
        args += ["--setenv", key, value]
    for key in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE", "DISPLAY", "DBUS_SESSION_BUS_ADDRESS",
                "SESSION_MANAGER", "SSH_AUTH_SOCK", "GPG_AGENT_INFO", "NOTIFY_SOCKET", "JOURNAL_STREAM",
                "SYSTEMD_EXEC_PID", "XDG_SESSION_ID", "XDG_VTNR", "XDG_SEAT", "XDG_SESSION_PATH"):
        args += ["--unsetenv", key]
    args += ["--chdir", "/workspace" if workspace else "/home/agent"]
    return args


def _lua_config(width: int, height: int) -> str:
    # Same settings as the hyprlang config, for realms that must evaluate IPC
    # dispatches as Lua like Cortetsu's host Hyprland does.
    return f"""hl.monitor({{ output = "", mode = "{width}x{height}@60", position = "0x0", scale = 1 }})
hl.config({{
    misc = {{
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        enable_anr_dialog = false,
        disable_watchdog_warning = true,
    }},
    input = {{ kb_layout = "us", follow_mouse = 1 }},
    cursor = {{ no_hardware_cursors = true }},
}})
"""


def lua_string(value: str) -> str:
    """Quote text as a Lua 5.5 string literal; every non-printable byte uses \\ddd."""
    out = []
    for byte in value.encode():
        if 0x20 <= byte < 0x7f and byte not in (0x22, 0x5c):
            out.append(chr(byte))
        else:
            out.append(f"\\{byte:03d}")
    return '"' + "".join(out) + '"'


def config_file(paths: RealmPaths, lua: bool) -> Path:
    return paths.config.with_suffix(".lua") if lua else paths.config


def _write_hypr_config(paths: RealmPaths, width: int, height: int, workspace: Path | None,
                       lua: bool = False) -> None:
    if width < 320 or height < 240 or width > 8192 or height > 8192:
        raise RealmError("la resolución debe estar entre 320x240 y 8192x8192")
    if lua:
        target = config_file(paths, lua)
        target.write_text(_lua_config(width, height))
        target.chmod(0o600)
        return
    lines = [
        f"monitor = , {width}x{height}@60, 0x0, 1",
        "misc {",
        "  disable_hyprland_logo = true",
        "  disable_splash_rendering = true",
        "  force_default_wallpaper = 0",
        "  enable_anr_dialog = false",
        "  disable_watchdog_warning = true",
        "}",
        "input {",
        "  kb_layout = us",
        "  follow_mouse = 1",
        "}",
        "cursor {",
        "  no_hardware_cursors = true",
        "}",
    ]
    if workspace:
        lines.append("# Workspace is exposed read-write at /workspace for agent-realm run.")
    paths.config.write_text("\n".join(lines) + "\n")
    paths.config.chmod(0o600)


def _readiness(paths: RealmPaths, child: subprocess.Popen[bytes], timeout: float = 25.0) -> dict[str, Any]:
    deadline = time.monotonic() + timeout
    last_problem = "Hyprland todavía no publicó su IPC privado"
    while time.monotonic() < deadline:
        if child.poll() is not None:
            try:
                log_tail = read_untrusted(paths.compositor_log, 5000)
            except OSError:
                log_tail = "(sin log de compositor)"
            raise RealmError(f"Hyprland terminó con código {child.returncode}:\n{log_tail}")
        try:
            meta = load_meta(paths)
        except RealmError:
            time.sleep(0.1)
            continue
        report = load_realm_report(paths) or {}
        if report.get("state") in {"failed", "crashed"}:
            # report["error"] is already stripped of control characters.
            raise RealmError(f"el supervisor del realm informó {report['state']}: "
                             f"{report.get('error', 'sin detalle')}")
        for key in ("signature", "wayland_display", "dbus_session_bus_address"):
            if key in report:
                meta[key] = report[key]
        sig = meta.get("signature")
        wayland = meta.get("wayland_display")
        if sig and wayland:
            env = _runtime_env(paths, wayland=wayland, signature=sig,
                               bus=meta.get("dbus_session_bus_address"))
            ipc = shutil.which("hyprctl", path="/usr/bin:/bin")
            if ipc:
                try:
                    r = subprocess.run([ipc, "-i", sig, "-j", "monitors"], env=env,
                                       capture_output=True, text=True, timeout=2)
                    if r.returncode == 0:
                        monitors = json.loads(r.stdout)
                        if not monitors:
                            created = subprocess.run([ipc, "-i", sig, "output", "create", "headless"],
                                                     env=env, capture_output=True, text=True, timeout=2)
                            if created.returncode != 0:
                                last_problem = created.stderr.strip() or created.stdout.strip() or last_problem
                                time.sleep(0.2)
                                continue
                            time.sleep(0.25)
                            r = subprocess.run([ipc, "-i", sig, "-j", "monitors"], env=env,
                                               capture_output=True, text=True, timeout=2)
                            monitors = json.loads(r.stdout) if r.returncode == 0 else []
                        if monitors:
                            monitor = monitors[0]
                            mon_name = monitor.get("name", "")
                            if not isinstance(mon_name, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", mon_name):
                                raise RealmError(f"nombre de monitor inesperado del realm: {mon_name!r}")
                            mode = f"{meta['width']}x{meta['height']}@60"
                            if meta.get("config_format") == "lua":
                                # `keyword` is hyprlang syntax; a Lua realm takes the rule as Lua.
                                rule = (f"hl.monitor({{ output = {lua_string(mon_name)}, mode = \"{mode}\", "
                                        'position = "0x0", scale = 1 })')
                                request = ["eval", rule]
                            else:
                                request = ["keyword", "monitor", f"{mon_name},{mode},0x0,1"]
                            configured = subprocess.run([ipc, "-i", sig, *request],
                                                         env=env, capture_output=True, text=True, timeout=2)
                            if configured.returncode != 0:
                                last_problem = configured.stderr.strip() or configured.stdout.strip() or last_problem
                                time.sleep(0.2)
                                continue
                            # Startup notices animate countdown bars in every frame; agents
                            # need still screenshots, and the supervisor already watches the compositor.
                            subprocess.run([ipc, "-i", sig, "dismissnotify"], env=env,
                                           capture_output=True, text=True, timeout=2)
                            meta["state"] = "running"
                            meta["started_at"] = time.time()
                            save_meta(paths, meta)
                            return meta
                    else:
                        last_problem = r.stderr.strip() or r.stdout.strip() or last_problem
                except (OSError, subprocess.SubprocessError, json.JSONDecodeError) as exc:
                    last_problem = str(exc)
        time.sleep(0.2)
    raise RealmError(f"Hyprland no completó el inicio en {timeout:.0f}s: {last_problem}")


def _check_startable(paths: RealmPaths) -> None:
    try:
        current = load_meta(paths)
    except RealmError as exc:
        if "no existe" in str(exc):
            if _realm_scope_units(paths.name):
                raise RealmError(f"hay scopes del realm {paths.name!r} sin metadatos; ejecuta recover") from exc
            return
        raise
    if process_alive(current):
        raise RealmError(f"la sesión {paths.name!r} ya está activa")
    active_scopes = sorted(
        unit for unit in _realm_scope_units(paths.name)
        if process_alive({"name": paths.name, "systemd_scope_unit": unit})
    )
    if active_scopes:
        raise RealmError(f"hay scopes activos del realm {paths.name!r} sin sesión activa; ejecuta recover: " +
                         ", ".join(active_scopes))


@lifecycle_serialized
def start(name: str, *, width: int = 1280, height: int = 800, ephemeral: bool = False,
          workspace: str | None = None, readonly_workspace: bool = False,
          compositor: str | None = None, timeout: float = 25.0, memory_max: str = "6G",
          cpu_quota: str = "200%", tasks_max: int = 512, lua: bool = False) -> dict[str, Any]:
    validate_name(name)
    paths = paths_for(name, create=True)
    _check_startable(paths)
    workspace_path = Path(workspace).expanduser().resolve(strict=True) if workspace else None
    if workspace_path and not workspace_path.is_dir():
        raise RealmError("--workspace debe apuntar a un directorio")
    hypr = _compositor_path(compositor)
    weston = _weston_path()
    render_node = _find_amd_render_node()
    if not render_node:
        raise RealmError("no se encontró un render node AMD; Weston GL no podrá dar dmabuf al Hyprland anidado")
    shim = xdg_version_shim_binary()
    from .input import virtual_input_binary
    input_client = virtual_input_binary()
    if not shutil.which("dbus-daemon", path="/usr/bin:/bin"):
        raise RealmError("dbus-daemon no está disponible")
    _validate_limits(memory_max, cpu_quota, tasks_max)
    _mkdir_private(paths.state)
    _mkdir_private(paths.control)
    (paths.state / REPORT_NAME).unlink(missing_ok=True)
    _mkdir_private(paths.home)
    _mkdir_private(paths.runtime)
    _mkdir_private(paths.parent_runtime)
    _write_hypr_config(paths, width, height, workspace_path, lua)
    for runtime_dir in (paths.runtime, paths.parent_runtime):
        for stale in runtime_dir.iterdir():
            if stale.is_socket() or stale.is_file():
                stale.unlink(missing_ok=True)
            elif stale.is_dir():
                shutil.rmtree(stale, ignore_errors=True)
    app_dir = paths.control / "apps"
    _mkdir_private(app_dir)
    meta = {
        "schema": 1,
        "name": name,
        "state": "starting",
        "created_at": time.time(),
        "width": width,
        "height": height,
        "ephemeral": bool(ephemeral),
        "workspace": str(workspace_path) if workspace_path else None,
        "readonly_workspace": bool(readonly_workspace),
        "config_format": "lua" if lua else "hyprlang",
        "compositor": hypr,
        "parent_compositor": weston,
        "render_node": render_node,
        "limits": {"memory_max": memory_max, "cpu_quota": cpu_quota, "tasks_max": tasks_max},
    }
    save_meta(paths, meta)
    realm_config = "/tmp/agent-realm-hyprland" + config_file(paths, lua).suffix
    supervisor = [
        "/usr/bin/python", *SUPERVISOR_MODULE_ARGV,
        "--compositor", hypr if hypr.startswith(("/usr/", "/bin/")) else "/tmp/agent-realm-Hyprland",
        "--config", realm_config,
        "--state-dir", "/var/lib/agent-realm",
        "--runtime-dir", paths.internal_runtime,
        "--parent-runtime-dir", paths.parent_internal_runtime,
        "--weston", weston,
        "--version-shim", "/tmp/agent-realm-xdg-version-shim.so",
        "--input-client", "/tmp/agent-realm-input-client",
        "--name", name,
        "--width", str(width), "--height", str(height),
    ]
    # The compositor must outlive this short-lived CLI process. Applications
    # launched through `run` use their own lifecycle and scope.
    args = _bwrap_prefix(paths, workspace=workspace_path, die_with_parent=False,
                         readonly_workspace=readonly_workspace, compositor=hypr, readonly_state=False,
                         include_parent=True, version_shim=shim, input_client=input_client)
    args += ["--ro-bind", str(config_file(paths, lua)), realm_config,
             "--setenv", "PYTHONPATH", "/app/src",
             "--ro-bind", str(repo_root()), "/app", "--", *supervisor]
    args, unit = _scope_command(name, args, memory_max=memory_max,
                                cpu_quota=cpu_quota, tasks_max=tasks_max)
    meta["systemd_scope_unit"] = unit
    save_meta(paths, meta)
    log = paths.log.open("ab", buffering=0)
    child = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                             env=_manager_env(), start_new_session=True, close_fds=True)
    meta.update({"leader_pid": child.pid, "leader_start_time": proc_start_time(child.pid),
                 "state": "starting", "supervisor_command": args[-8:]})
    save_meta(paths, meta)
    try:
        ready = _readiness(paths, child, timeout=timeout)
        ready["leader_pid"] = child.pid
        ready["leader_start_time"] = proc_start_time(child.pid)
        ready["workspace"] = str(workspace_path) if workspace_path else None
        ready["readonly_workspace"] = bool(readonly_workspace)
        ready["ephemeral"] = bool(ephemeral)
        save_meta(paths, ready)
        return ready
    except BaseException as startup_error:
        cleanup_error = None
        try:
            cleanup_groups(paths)
        except Exception as exc:
            cleanup_error = exc
        try:
            meta = load_meta(paths)
            meta["state"] = "cleanup_failed" if cleanup_error else "failed"
            if cleanup_error:
                meta["cleanup_error"] = str(cleanup_error)
            save_meta(paths, meta)
        except RealmError:
            pass
        if cleanup_error:
            raise RealmError(f"falló el inicio y no se pudo detener su scope: {cleanup_error}") from startup_error
        raise
    finally:
        log.close()


def _realm_env(paths: RealmPaths, meta: dict[str, Any]) -> dict[str, str]:
    if not meta.get("signature") or not meta.get("wayland_display"):
        raise RealmError("la sesión aún no ha publicado sockets Wayland e IPC")
    env = _runtime_env(paths, wayland=meta["wayland_display"],
                       signature=meta["signature"],
                       bus=meta.get("dbus_session_bus_address"))
    return env


def realm_bwrap(paths: RealmPaths, meta: dict[str, Any], *, workspace: str | None = None,
                readonly_workspace: bool | None = None, die_with_parent: bool = False,
                mount_project: bool = False) -> list[str]:
    mount = Path(workspace).expanduser().resolve(strict=True) if workspace else None
    if mount and not mount.is_dir():
        raise RealmError("el workspace debe ser un directorio")
    if mount is None and meta.get("workspace"):
        mount = Path(meta["workspace"])
    readonly = bool(meta.get("readonly_workspace")) if readonly_workspace is None else readonly_workspace
    args = _bwrap_prefix(paths, workspace=mount, readonly_workspace=readonly,
                         die_with_parent=die_with_parent)
    env = _realm_env(paths, meta)
    for key, value in env.items():
        args += ["--setenv", key, value]
    if mount_project:
        # Only code and scenarios, read-only: the checkout may hold private logs and evidence.
        args += ["--ro-bind", str(repo_root() / "src"), "/app/src",
                 "--ro-bind", str(repo_root() / "scenarios"), "/app/scenarios",
                 "--setenv", "PYTHONPATH", "/app/src"]
    args += ["--"]
    return args


def _stop_failed_app_scope(name: str, unit: str, proc: subprocess.Popen[bytes]) -> None:
    if not re.fullmatch(rf"agent-realm-{re.escape(name)}-[0-9a-f]{{10}}\.scope", unit):
        raise RealmError("scope de app fuera del patrón del realm; no se intentó detenerlo")
    try:
        control_scope(name, unit, "stop")
    except RealmError:
        pass
    finally:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=2)
    control_scope(name, unit, "stop")
    if process_alive({"name": name, "systemd_scope_unit": unit}):
        raise RealmError(f"el scope de app continúa activo tras fallar su registro: {unit}")


def run(name: str, command: list[str], *, workspace: str | None = None,
        readonly_workspace: bool | None = None, detach: bool = False,
        compositor_child: bool = False,
        memory_max: str | None = None, cpu_quota: str | None = None,
        tasks_max: int | None = None, mount_project: bool = False) -> dict[str, Any]:
    if not command:
        raise RealmError("run requiere un comando después de --")
    paths = paths_for(name)
    with lifecycle_lock(paths):
        meta = load_meta(paths)
        if not process_alive(meta) or meta.get("state") != "running":
            raise RealmError(f"la sesión {name!r} no está activa")
        requested_workspace = Path(workspace).expanduser().resolve(strict=True) if workspace else None
        stored_workspace = Path(meta["workspace"]) if meta.get("workspace") else None
        if requested_workspace and requested_workspace != stored_workspace:
            raise RealmError("el workspace debe montarse al iniciar el realm con --workspace")
        if readonly_workspace and not meta.get("readonly_workspace"):
            raise RealmError("no se puede endurecer un mount ya activo; inicia el realm con --readonly-workspace")
        if compositor_child:
            if not detach:
                raise RealmError("--compositor-child requiere --detach; el compositor no informa el código de salida")
            if memory_max or cpu_quota or tasks_max is not None:
                raise RealmError("--compositor-child usa los límites del scope del realm, no límites por app")
            if meta.get("config_format") == "lua":
                dispatch = ["dispatch", f"hl.dsp.exec_cmd({lua_string(shlex.join(command))})"]
            else:
                dispatch = ["dispatch", "exec", shlex.join(command)]
            result = private_call(name, dispatch)
            if result.returncode != 0:
                raise RealmError(result.stderr.strip() or result.stdout.strip() or
                                 "Hyprland no aceptó el comando en el namespace del compositor")
            return {"pid": None, "command": command, "detached": True,
                    "launch_mode": "compositor-child", "dispatch_accepted": True}
        args = realm_bwrap(paths, meta, readonly_workspace=readonly_workspace,
                           die_with_parent=False, mount_project=mount_project)
        # Replace bwrap's sentinel with the caller's argv verbatim.
        args = args[:-1] + command
        app_dir = paths.control / "apps"
        _mkdir_private(app_dir)
        limits = meta.get("limits", {})
        args, unit = _scope_command(name, args,
                                    memory_max=memory_max or limits.get("memory_max", "6G"),
                                    cpu_quota=cpu_quota or limits.get("cpu_quota", "200%"),
                                    tasks_max=tasks_max or limits.get("tasks_max", 512))
        proc = subprocess.Popen(args, stdin=subprocess.DEVNULL,
                                stdout=None if not detach else subprocess.DEVNULL,
                                stderr=None if not detach else subprocess.DEVNULL,
                                start_new_session=True, env=_manager_env())
        record = {"pid": proc.pid, "start_time": proc_start_time(proc.pid), "command": command,
                  "started_at": time.time(), "systemd_scope_unit": unit}
        record_path = app_dir / f"{proc.pid}.json"
        temp_path = record_path.with_suffix(record_path.suffix + ".tmp")
        try:
            temp_path.write_text(json.dumps(record, ensure_ascii=False) + "\n")
            temp_path.chmod(0o600)
            os.replace(temp_path, record_path)
        except OSError as exc:
            cleanup_errors = []
            try:
                _stop_failed_app_scope(name, unit, proc)
            except Exception as cleanup_error:
                cleanup_errors.append(f"no se pudo limpiar {unit}: {cleanup_error}")
            try:
                temp_path.unlink(missing_ok=True)
            except OSError as cleanup_error:
                cleanup_errors.append(f"no se pudo retirar el temporal {temp_path.name}: {cleanup_error}")
            if cleanup_errors:
                raise RealmError(f"no se pudo guardar el registro de la app ({exc}); " +
                                 "; ".join(cleanup_errors)) from exc
            raise RealmError(f"no se pudo guardar el registro de la app; el scope {unit} fue detenido: {exc}") from exc
    if detach:
        return {"pid": proc.pid, "command": command, "detached": True}
    try:
        code = proc.wait()
    finally:
        record_path.unlink(missing_ok=True)
    return {"pid": proc.pid, "command": command, "exit_code": code, "detached": False}


@lifecycle_serialized
def stop(name: str, *, remove_ephemeral: bool = True) -> dict[str, Any]:
    paths = paths_for(name)
    try:
        meta = load_meta(paths)
    except RealmError as exc:
        if "no existe" in str(exc):
            return {"name": name, "state": "absent"}
        raise
    from .observer import notify_realm_stopped
    notify_realm_stopped(name)  # revoke viewer access before the frames disappear
    cleanup_groups(paths)
    meta["state"] = "stopped"
    meta["stopped_at"] = time.time()
    save_meta(paths, meta)
    for runtime_dir in (paths.runtime, paths.parent_runtime):
        for path in runtime_dir.iterdir() if runtime_dir.exists() else ():
            if path.is_socket() or path.is_file():
                path.unlink(missing_ok=True)
            elif path.is_dir():
                shutil.rmtree(path, ignore_errors=True)
    if meta.get("ephemeral") and remove_ephemeral:
        shutil.rmtree(data_root() / name, ignore_errors=True)
    return {"name": name, "state": "stopped", "ephemeral_home_removed": bool(meta.get("ephemeral") and remove_ephemeral)}


@lifecycle_serialized
def pause(name: str, paused: bool) -> dict[str, Any]:
    paths = paths_for(name)
    meta = load_meta(paths)
    if not process_alive(meta):
        raise RealmError(f"la sesión {name!r} no está activa")
    if meta.get("state") not in {"running", "paused", "transition-error"}:
        raise RealmError(f"la sesión {name!r} tiene un estado que no admite pause/resume: "
                         f"{meta.get('state')!r}")
    unit = meta.get("systemd_scope_unit")
    if not isinstance(unit, str) or not _valid_scope_unit(name, unit):
        raise RealmError("la sesión no tiene un scope systemd supervisable")

    if paused:
        apps = app_groups(paths)
        app_units = set()
        for app in apps:
            app_unit = app.get("systemd_scope_unit")
            if not isinstance(app_unit, str) or not _valid_scope_unit(name, app_unit):
                raise RealmError("una app legacy no tiene un scope supervisable y no se puede pausar")
            if app_unit != unit:
                app_units.add(app_unit)
        active_units = sorted(
            scope for scope in _realm_scope_units(name)
            if scope != unit and process_alive({"name": name, "systemd_scope_unit": scope})
        )
        unregistered_active = sorted(set(active_units) - app_units)
        if unregistered_active:
            raise RealmError("hay apps activas sin registro persistido; no se pausó el realm: " +
                             ", ".join(unregistered_active))
        units = sorted(app_units) + [unit]
        action = "freeze"
        target_state = "paused"
    else:
        # Resume from systemd's exact realm scopes, even when an app record is
        # missing or corrupt. App groups thaw first so the compositor is last.
        active_units = sorted(
            scope for scope in _realm_scope_units(name)
            if scope != unit and process_alive({"name": name, "systemd_scope_unit": scope})
        )
        units = active_units + [unit]
        action = "thaw"
        target_state = "running"

    _transition_scopes(paths, meta, units, action, target_state)
    return {"name": name, "state": meta["state"]}


def _transition_scopes(paths: RealmPaths, meta: dict[str, Any], units: list[str],
                       action: str, target_state: str) -> None:
    target_freezer_state = "frozen" if action == "freeze" else "running"
    original_meta = dict(meta)
    original_freezer_states = {unit: scope_freezer_state(paths.name, unit) for unit in units}
    attempted: list[str] = []
    try:
        for unit in units:
            if original_freezer_states[unit] == target_freezer_state:
                continue
            attempted.append(unit)
            control_scope(paths.name, unit, action)
        meta["state"] = target_state
        meta.pop("transition_error", None)
        meta.pop("transition_error_at", None)
        save_meta(paths, meta)
        return
    except BaseException as exc:
        rollback_errors = []
        for unit in reversed(attempted):
            try:
                original_action = "freeze" if original_freezer_states[unit] == "frozen" else "thaw"
                control_scope(paths.name, unit, original_action)
            except BaseException as rollback_error:
                rollback_errors.append(f"{unit}: {rollback_error}")

        meta.clear()
        meta.update(original_meta)
        if rollback_errors:
            meta["state"] = "transition-error"
            meta["transition_error"] = str(exc) + "; rollback: " + "; ".join(rollback_errors)
            meta["transition_error_at"] = time.time()
        transition_error_persisted = False
        try:
            save_meta(paths, meta)
            transition_error_persisted = meta.get("state") == "transition-error"
        except BaseException as save_error:
            rollback_errors.append(f"no se pudieron guardar metadatos restaurados: {save_error}")
            if meta.get("state") != "transition-error":
                meta["state"] = "transition-error"
                meta["transition_error"] = str(exc)
                meta["transition_error_at"] = time.time()
            try:
                save_meta(paths, meta)
                transition_error_persisted = True
            except BaseException as transition_save_error:
                rollback_errors.append(f"no se pudo guardar estado transition-error: {transition_save_error}")

        if rollback_errors:
            marker = ("el estado transition-error quedó guardado" if transition_error_persisted
                      else "no se pudo guardar el estado transition-error")
            raise RealmError("falló la transición de scopes y la restauración no fue completa; " +
                             marker + ": " + "; ".join(rollback_errors)) from exc
        if not isinstance(exc, Exception):
            raise
        raise RealmError(f"falló la transición de scopes; se restauró el estado previo: {exc}") from exc


@lifecycle_serialized
def recover(name: str) -> dict[str, Any]:
    paths = paths_for(name, create=True)
    try:
        old = load_meta(paths)
    except RealmError as exc:
        if "no existe" not in str(exc) and "dañados" not in str(exc) and "no corresponden" not in str(exc):
            raise
        old = {"schema": 1, "name": name}
        cleanup_groups(paths, allow_corrupt_session_meta=True)
    else:
        if process_alive(old):
            raise RealmError(f"la sesión {name!r} sigue activa; deténla antes de recover")
        cleanup_groups(paths, allow_corrupt_session_meta=True)
    for runtime_dir in (paths.runtime, paths.parent_runtime):
        for entry in runtime_dir.iterdir() if runtime_dir.exists() else ():
            if entry.is_file() or entry.is_socket():
                entry.unlink(missing_ok=True)
            elif entry.is_dir():
                shutil.rmtree(entry, ignore_errors=True)
    old["state"] = "recovered"
    old["recovered_at"] = time.time()
    save_meta(paths, old)
    return {"name": name, "state": "recovered", "runtime_directory": str(paths.runtime),
            "parent_runtime_directory": str(paths.parent_runtime)}


def _require_realm_ipc_socket(paths: RealmPaths, signature: str) -> None:
    """hyprctl must reach this realm's compositor, never fall back to another instance."""
    if not re.fullmatch(r"[A-Za-z0-9_]{1,128}", signature):
        raise RealmError("firma IPC del realm inválida")
    sock = paths.runtime / "hypr" / signature / ".socket.sock"
    try:
        info = sock.lstat()
    except OSError as exc:
        raise RealmError(f"el realm {paths.name!r} no tiene socket IPC propio: {exc}") from exc
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise RealmError(f"el socket IPC del realm {paths.name!r} no es un socket propio")


def stop_app(name: str, pid: int) -> dict[str, Any]:
    """Stop one app started by `run`, through its recorded systemd scope."""
    if isinstance(pid, bool) or not isinstance(pid, int) or pid <= 1:
        raise RealmError("identificador de app inválido")
    paths = paths_for(name)
    with lifecycle_lock(paths):
        record_path = paths.control / "apps" / f"{pid}.json"
        try:
            record = json.loads(record_path.read_text())
        except FileNotFoundError as exc:
            raise RealmError(f"no hay una app registrada con id {pid}") from exc
        except (OSError, ValueError) as exc:
            raise RealmError(f"registro de app ilegible: {exc}") from exc
        unit = record.get("systemd_scope_unit") if isinstance(record, dict) else None
        if not isinstance(unit, str) or not _valid_scope_unit(name, unit):
            raise RealmError("la app no tiene un scope del realm; no se detiene por PID")
        if unit == load_meta(paths).get("systemd_scope_unit"):
            raise RealmError("el registro apunta al scope del compositor; usa stop para el realm")
        control_scope(name, unit, "stop")
        if process_alive({"name": name, "systemd_scope_unit": unit}):
            raise RealmError(f"la app sigue activa tras detener {unit}")
        record_path.unlink(missing_ok=True)
    return {"app_id": pid, "systemd_scope_unit": unit, "state": "stopped"}


def private_call(name: str, command: list[str], *, timeout: float = 4.0) -> subprocess.CompletedProcess[str]:
    paths = paths_for(name)
    meta = load_meta(paths)
    if not process_alive(meta):
        raise RealmError(f"la sesión {name!r} no está activa")
    env = _realm_env(paths, meta)
    _require_realm_ipc_socket(paths, meta["signature"])
    hyprctl = shutil.which("hyprctl", path="/usr/bin:/bin")
    if not hyprctl:
        raise RealmError("no se encuentra hyprctl")
    # Every request names this realm's signature explicitly; no ambient host default is used.
    return subprocess.run([hyprctl, "-i", meta["signature"], *command], env=env,
                          capture_output=True, text=True, timeout=timeout)


def session_records() -> list[dict[str, Any]]:
    result = []
    root = state_root()
    if not root.exists():
        return result
    for folder in sorted(root.iterdir()):
        if not folder.is_dir():
            continue
        try:
            paths = paths_for(folder.name)
            meta = load_meta(paths)
        except (RealmError, OSError):
            continue
        meta["alive"] = process_alive(meta)
        result.append(meta)
    return result
