from __future__ import annotations

import argparse
import json
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any

from . import __version__
from . import input as vinput
from . import observer
from .capture import capture
from .paths import RealmError, paths_for, state_root
from .process import (
    read_untrusted,
    supervisor_present,
    _realm_scope_units,
    _valid_scope_unit,
    load_meta,
    proc_start_time,
    process_alive,
    save_meta,
    signal_group,
    stop_group,
)
from .runtime import (
    _compositor_path,
    _find_amd_render_node,
    _manager_env,
    _scope_command,
    pause,
    private_call,
    recover,
    run as run_command,
    session_records,
    start,
    stop,
)


def _json(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, indent=2, sort_keys=True))


def _proc_stat(pid: int) -> list[str] | None:
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
        return raw[raw.rfind(")") + 2 :].split()
    except OSError:
        return None


def _proc_scope_metrics(proc_root: Path, scope_units: set[str]) -> tuple[int, int, int]:
    """Return process count, CPU ticks and PSS KiB for exact systemd scope cgroups."""
    pss_kb = cpu_ticks = count = 0
    if not scope_units:
        return count, cpu_ticks, pss_kb
    try:
        entries = list(proc_root.iterdir())
    except OSError:
        return count, cpu_ticks, pss_kb
    for entry in entries:
        if not entry.name.isdigit():
            continue
        try:
            cgroup_lines = (entry / "cgroup").read_text().splitlines()
        except OSError:
            continue
        belongs_to_scope = False
        for line in cgroup_lines:
            fields = line.split(":", 2)
            if len(fields) != 3:
                continue
            components = Path(fields[2]).parts
            if any(component in scope_units for component in components):
                belongs_to_scope = True
                break
        if not belongs_to_scope:
            continue

        count += 1
        try:
            raw_stat = (entry / "stat").read_text()
            fields = raw_stat[raw_stat.rfind(")") + 2 :].split()
            cpu_ticks += int(fields[11]) + int(fields[12])
        except (OSError, ValueError, IndexError):
            pass
        try:
            rollup = (entry / "smaps_rollup").read_text()
            for line in rollup.splitlines():
                if line.startswith("Pss:"):
                    pss_kb += int(line.split()[1])
                    break
        except (OSError, ValueError, IndexError):
            pass
    return count, cpu_ticks, pss_kb


def _resource_metrics(meta: dict[str, Any], paths: Any, *, proc_root: Path = Path("/proc")) -> dict[str, Any]:
    name = meta.get("name")
    scope_units: set[str] = set()
    session_unit = meta.get("systemd_scope_unit")
    if isinstance(name, str) and isinstance(session_unit, str) and _valid_scope_unit(name, session_unit):
        scope_units.add(session_unit)
    if isinstance(name, str):
        for unit in _realm_scope_units(name):
            if process_alive({"name": name, "systemd_scope_unit": unit}):
                scope_units.add(unit)

    count, cpu_ticks, pss_kb = _proc_scope_metrics(proc_root, scope_units)
    try:
        hz = os.sysconf("SC_CLK_TCK")
    except (ValueError, OSError):
        hz = 100
    gpu_busy = None
    busy_path = None
    if _find_amd_render_node():
        for candidate in Path("/sys/class/drm").glob("card*/device/gpu_busy_percent"):
            vendor = candidate.parent.joinpath("vendor")
            try:
                if vendor.read_text().strip().lower() == "0x1002":
                    gpu_busy = int(candidate.read_text().strip())
                    busy_path = str(candidate)
                    break
            except (OSError, ValueError):
                continue
    return {"process_count": count, "cpu_seconds": round(cpu_ticks / hz, 3),
            "pss_kib": pss_kb, "amd_gpu_busy_percent_global": gpu_busy,
            "resource_scope_units": sorted(scope_units),
            "resource_source": "procesos en cgroups systemd exactos del realm, sumados desde /proc",
            "amd_gpu_busy_source": busy_path,
            "gpu_note": "GPU busy is a device-wide sample and includes host applications." if gpu_busy is not None else None}


def _hypr_json(name: str, command: list[str]) -> Any:
    result = private_call(name, ["-j", *command])
    if result.returncode != 0:
        raise RealmError(result.stderr.strip() or result.stdout.strip() or "IPC realm falló")
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise RealmError(f"hyprctl devolvió JSON inválido: {exc}") from exc


def _status(meta: dict[str, Any]) -> dict[str, Any]:
    paths = paths_for(meta["name"])
    meta = dict(meta)
    alive = process_alive(meta)
    meta["alive"] = alive
    if not alive and meta.get("state") in {"running", "paused", "starting"}:
        meta["state"] = "stale"
    unit = meta.get("systemd_scope_unit")
    if alive and isinstance(unit, str):
        meta["supervised"] = supervisor_present(unit)
        if not meta["supervised"] and meta.get("state") == "running":
            # Compositor still serves IPC but nobody records crashes; `stop` cleans the scope.
            meta["state"] = "degraded"
    if alive and meta.get("state") in {"running", "degraded"}:
        try:
            meta["ipc_reachable"] = bool(_hypr_json(meta["name"], ["monitors"]))
        except (RealmError, OSError, subprocess.SubprocessError):
            meta["ipc_reachable"] = False
    return meta


def _screenshot(name: str, output: str | None = None, monitor: str | None = None) -> Path:
    frame = capture(name, monitor=monitor)
    directory = paths_for(name).control / "captures"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = Path(output).expanduser() if output else directory / f"{time.strftime('%Y%m%d-%H%M%S')}.png"
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    fd = os.open(target, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    with os.fdopen(fd, "wb") as handle:
        handle.write(frame.data)
    return target


def _doctor() -> dict[str, Any]:
    tools = {}
    for name in ("Hyprland", "weston", "hyprctl", "bwrap", "dbus-daemon", "systemd-run", "grim", "wtype",
                 "wayland-scanner", "pkg-config", "cc", "qs"):
        path = shutil.which(name, path="/usr/local/bin:/usr/bin:/bin")
        tools[name] = path
    compositor = None
    if tools["Hyprland"]:
        try:
            with tempfile.TemporaryDirectory(prefix="agent-realm-doctor-") as private_home:
                os.chmod(private_home, 0o700)
                result = subprocess.run([tools["Hyprland"], "--version"], capture_output=True,
                                        text=True, timeout=3,
                                        env={"PATH": "/usr/bin:/bin", "HOME": private_home,
                                             "XDG_RUNTIME_DIR": private_home,
                                             "XDG_CONFIG_HOME": private_home + "/config"})
            compositor = (result.stdout or result.stderr).strip()
        except (OSError, subprocess.SubprocessError):
            compositor = "ejecutable encontrado; no se pudo leer la versión"
    namespace_ok = False
    namespace_detail = None
    if tools["bwrap"]:
        probe = subprocess.run([tools["bwrap"], "--unshare-user", "--unshare-pid", "--unshare-uts",
                               "--new-session", "--clearenv", "--dev", "/dev", "--proc", "/proc",
                               "--ro-bind", "/usr", "/usr", "--symlink", "usr/bin", "/bin",
                               "--symlink", "usr/bin", "/sbin", "--symlink", "usr/lib", "/lib",
                               "--symlink", "usr/lib", "/lib64", "--", "/usr/bin/true"],
                              capture_output=True, text=True, timeout=5,
                              env={"PATH": "/usr/bin:/bin", "HOME": "/nonexistent"})
        namespace_ok = probe.returncode == 0
        namespace_detail = (probe.stderr.strip() or f"exit={probe.returncode}") if not namespace_ok else "namespace user/pid/uts disponible"
    scope_ok = False
    scope_detail = None
    if tools["systemd-run"]:
        try:
            prefix, _unit = _scope_command("doctor", ["/usr/bin/true"], memory_max="512M",
                                           cpu_quota="20%", tasks_max=64)
            probe = subprocess.run(prefix, capture_output=True, text=True, timeout=8, env=_manager_env())
            scope_ok = probe.returncode == 0
            scope_detail = (probe.stderr.strip() or f"exit={probe.returncode}") if not scope_ok else \
                "scope transitorio acepta MemoryMax, CPUQuota y TasksMax"
        except (RealmError, OSError, subprocess.SubprocessError) as exc:
            scope_detail = str(exc)
    virtual_pointer = None
    try:
        path = vinput.virtual_input_binary()
        virtual_pointer = str(path)
    except (RealmError, OSError, subprocess.SubprocessError) as exc:
        virtual_pointer = f"no disponible: {exc}"
    parent_shim = None
    try:
        from .runtime import xdg_version_shim_binary
        parent_shim = str(xdg_version_shim_binary())
    except (RealmError, OSError, subprocess.SubprocessError) as exc:
        parent_shim = f"no disponible: {exc}"
    return {"version": __version__, "compositor_version": compositor, "tools": tools,
            "user_namespaces": {"available": namespace_ok, "detail": namespace_detail},
            "resource_scopes": {"available": scope_ok, "detail": scope_detail},
            "amd_render_node": _find_amd_render_node(), "virtual_pointer_client": virtual_pointer,
            "weston_parent": {"executable": tools["weston"], "renderer": "GL headless sobre render node AMD",
                              "compatibility_shim": parent_shim},
            "scope": "bwrap separa HOME/XDG, sockets, PIDs y dispositivos; conserva el namespace de red y comparte kernel/GPU.",
            "host_actions": "doctor no inicia ni modifica Hyprland o Quickshell del anfitrión."}


def _observe(args: argparse.Namespace) -> dict[str, Any]:
    if args.interval < 0.25 or args.interval > 10:
        raise RealmError("--interval debe estar entre 0.25 y 10 segundos")
    if args.idle_timeout < 30 or args.idle_timeout > 86400:
        raise RealmError("--idle-timeout debe estar entre 30 y 86400 segundos")
    for action in ("revoke", "stop", "status"):
        if getattr(args, action):
            reply = observer.control_request(args.name, action)
            return reply or {"name": args.name, "observer": "absent"}
    if args.foreground:
        def ready(obs: observer.Observer) -> None:
            print(f"Observador de solo lectura: {obs.origin}/ (requiere autorización)", flush=True)
            if args.open:
                observer.open_browser(str(obs.issue_launch_file()))
        observer.serve(args.name, port=args.port, interval=args.interval, monitor=args.monitor,
                       idle_timeout=args.idle_timeout, ready=ready)
        return {"name": args.name, "observer": "stopped"}
    status = observer.ensure_running(args.name, port=args.port, interval=args.interval,
                                     monitor=args.monitor, idle_timeout=args.idle_timeout)
    result = {"name": args.name, "observer": "running", "url": status["url"], "pid": status["pid"]}
    if args.open:
        launch = observer.control_request(args.name, "launch")
        observer.open_browser(launch["launch_file"])
        result["opened"] = True
    elif args.launch_file:
        result["launch_file"] = observer.control_request(args.name, "launch")["launch_file"]
    return result


def _simulate(args: argparse.Namespace) -> Any:
    from .simulation import host, scenario
    if args.list:
        return scenario.list_scenarios()
    if not args.name:
        raise RealmError("simulate necesita el nombre del realm")
    if args.stop:
        return host.stop(args.name)
    if args.scenario:
        result = host.start(args.name, args.scenario)
        if args.set or args.event:
            result = host.control(args.name, assignments=args.set, event=args.event)
        return result
    if args.set or args.event or args.reset:
        return host.control(args.name, assignments=args.set, event=args.event, reset=args.reset)
    return host.status(args.name)


def _profile(args: argparse.Namespace) -> Any:
    from . import profiles
    if args.profile_action == "set":
        start: dict[str, Any] = {key: getattr(args, key) for key in ("width", "height", "workspace")
                                 if getattr(args, key) is not None}
        if args.workspace:
            start["workspace"] = str(Path(args.workspace).expanduser().resolve(strict=True))
        if args.lua:
            start["lua"] = True
        raw = {"realm": args.realm, "lifecycle": args.lifecycle, "autostart": not args.no_autostart,
               "capabilities": [c.strip() for c in args.capabilities.split(",") if c.strip()], "start": start}
        return {"path": str(profiles.profiles_path()), **profiles.save_profile(args.name, raw).describe()}
    if args.profile_action == "list":
        return [p.describe() for p in profiles.load_all().values()]
    if args.profile_action == "show":
        profile = profiles.load(args.name)
        return {**profile.describe(), "start": profile.start}
    return {"name": args.name, "removed": profiles.remove_profile(args.name)}


def parser() -> argparse.ArgumentParser:
    root = argparse.ArgumentParser(prog="agent-realm", description="Ciclo de vida e interacción con Hyprland headless aislado")
    root.add_argument("--version", action="version", version=__version__)
    commands = root.add_subparsers(dest="subcommand", required=True)

    p = commands.add_parser("start", help="inicia una sesión privada")
    p.add_argument("name")
    p.add_argument("--width", type=int, default=1280)
    p.add_argument("--height", type=int, default=800)
    p.add_argument("--ephemeral", action="store_true", help="borra el HOME privado al detener")
    p.add_argument("--workspace", help="directorio del proyecto visible como /workspace")
    p.add_argument("--readonly-workspace", action="store_true")
    p.add_argument("--compositor", help="Hyprland instalado; por defecto busca /usr/bin/Hyprland")
    p.add_argument("--timeout", type=float, default=25)
    p.add_argument("--memory-max", default="6G", help="límite de memoria del scope de systemd (6G)")
    p.add_argument("--cpu-quota", default="200%", help="cuota de CPU del scope de systemd (200%% = 2 cores)")
    p.add_argument("--tasks-max", type=int, default=512)
    p.add_argument("--lua", action="store_true",
                   help="configura Hyprland en Lua; IPC dispatch evalúa Lua como en Cortetsu")

    p = commands.add_parser("stop", help="detiene la sesión y sus procesos")
    p.add_argument("name")
    p = commands.add_parser("pause", help="suspende procesos del realm")
    p.add_argument("name")
    p = commands.add_parser("resume", help="reanuda procesos del realm")
    p.add_argument("name")
    p = commands.add_parser("recover", help="limpia sockets y registros de una sesión caída")
    p.add_argument("name")
    p = commands.add_parser("status", help="muestra estado de sesiones")
    p.add_argument("name", nargs="?")
    p = commands.add_parser("inspect", help="muestra IPC, geometría y mediciones del realm")
    p.add_argument("name")
    p = commands.add_parser("run", help="ejecuta un programa con el entorno privado del realm")
    p.add_argument("name")
    p.add_argument("--workspace")
    p.add_argument("--readonly-workspace", action="store_true", default=None)
    p.add_argument("--detach", action="store_true")
    p.add_argument("--compositor-child", action="store_true",
                    help="ejecuta dentro del namespace PID de Hyprland para integrar apps gráficas y Overview")
    p.add_argument("--memory-max")
    p.add_argument("--cpu-quota")
    p.add_argument("--tasks-max", type=int)
    p.add_argument("command", nargs=argparse.REMAINDER)
    p = commands.add_parser("screenshot", help="captura un output del realm con grim")
    p.add_argument("name")
    p.add_argument("--output")
    p.add_argument("--monitor")
    p = commands.add_parser("click", help="clic virtual sobre el seat del realm")
    p.add_argument("name"); p.add_argument("x", type=int); p.add_argument("y", type=int)
    p.add_argument("--button", choices=("left", "right", "middle", "back", "forward"), default="left")
    p.add_argument("--count", type=int, default=1)
    p = commands.add_parser("move", help="mueve el puntero virtual")
    p.add_argument("name"); p.add_argument("x", type=int); p.add_argument("y", type=int)
    p = commands.add_parser("drag", help="arrastra con el puntero virtual")
    p.add_argument("name"); p.add_argument("x1", type=int); p.add_argument("y1", type=int)
    p.add_argument("x2", type=int); p.add_argument("y2", type=int)
    p.add_argument("--button", choices=("left", "right", "middle"), default="left")
    p = commands.add_parser("key", help="envía una tecla o chord virtual")
    p.add_argument("name"); p.add_argument("chord")
    p = commands.add_parser("type", help="escribe texto con un teclado Wayland virtual")
    p.add_argument("name"); p.add_argument("text"); p.add_argument("--delay-ms", type=int, default=5)
    p = commands.add_parser("scroll", help="envía rueda virtual; dx/dy usan píxeles Wayland")
    p.add_argument("name"); p.add_argument("x", type=int); p.add_argument("y", type=int)
    p.add_argument("dx", type=int, nargs="?", default=0); p.add_argument("dy", type=int, nargs="?", default=0)
    p = commands.add_parser("windows", help="lista ventanas del realm mediante IPC privado")
    p.add_argument("name")
    p = commands.add_parser("logs", help="muestra logs del supervisor y compositor")
    p.add_argument("name"); p.add_argument("--tail", type=int, default=100)
    p = commands.add_parser("doctor", help="verifica herramientas y namespaces sin iniciar sesiones")
    p = commands.add_parser("observe", help="observador autenticado de solo lectura en localhost")
    p.add_argument("name")
    p.add_argument("--open", action="store_true", help="autoriza y abre el navegador predeterminado")
    p.add_argument("--launch-file", action="store_true",
                   help="crea un archivo de lanzamiento de un solo uso y muestra su ruta")
    p.add_argument("--revoke", action="store_true", help="invalida todas las sesiones del visor")
    p.add_argument("--stop", action="store_true", help="detiene el observador; el realm sigue activo")
    p.add_argument("--status", action="store_true")
    p.add_argument("--foreground", action="store_true", help="sirve en este proceso hasta Ctrl+C")
    p.add_argument("--port", type=int, default=0)
    p.add_argument("--interval", type=float, default=0.5)
    p.add_argument("--idle-timeout", type=float, default=900.0,
                   help="segundos sin visores autorizados antes de cerrarse (900)")
    p.add_argument("--monitor")

    p = commands.add_parser("simulate", help="servicios del sistema simulados dentro del realm")
    p.add_argument("name", nargs="?", help="realm; no hace falta con --list")
    p.add_argument("--scenario", help="inicia la simulación o cambia de escenario")
    p.add_argument("--list", action="store_true", help="lista los escenarios disponibles")
    p.add_argument("--status", action="store_true")
    p.add_argument("--set", action="append", metavar="RUTA=VALOR",
                   help="cambia el estado, p. ej. upower.battery.percentage=12 (repetible)")
    p.add_argument("--event", choices=("wifi-scan", "bt-discover", "pipewire-restart"))
    p.add_argument("--reset", action="store_true", help="vuelve al estado inicial del escenario")
    p.add_argument("--stop", action="store_true", help="detiene servicios simulados y bus privado")

    p = commands.add_parser("profile", help="asocia clientes MCP a realms y capacidades")
    actions = p.add_subparsers(dest="profile_action", required=True)
    q = actions.add_parser("set", help="crea o reemplaza un perfil")
    q.add_argument("name")
    q.add_argument("--realm", required=True)
    q.add_argument("--capabilities", default="observe,control,admin",
                   help="lista separada por comas de observe, control y admin")
    q.add_argument("--lifecycle", choices=("persistent", "ephemeral"), default="persistent")
    q.add_argument("--no-autostart", action="store_true", help="no iniciar el realm desde el MCP")
    q.add_argument("--width", type=int)
    q.add_argument("--height", type=int)
    q.add_argument("--lua", action="store_true")
    q.add_argument("--workspace")
    actions.add_parser("list", help="muestra todos los perfiles")
    q = actions.add_parser("show")
    q.add_argument("name")
    q = actions.add_parser("remove")
    q.add_argument("name")
    return root


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        if args.subcommand == "start":
            _json(start(args.name, width=args.width, height=args.height, ephemeral=args.ephemeral,
                        workspace=args.workspace, readonly_workspace=args.readonly_workspace,
                        compositor=args.compositor, timeout=args.timeout,
                        memory_max=args.memory_max, cpu_quota=args.cpu_quota, tasks_max=args.tasks_max,
                        lua=args.lua))
        elif args.subcommand == "stop":
            _json(stop(args.name))
        elif args.subcommand == "pause":
            _json(pause(args.name, True))
        elif args.subcommand == "resume":
            _json(pause(args.name, False))
        elif args.subcommand == "recover":
            _json(recover(args.name))
        elif args.subcommand == "status":
            records = session_records()
            if args.name:
                found = next((r for r in records if r["name"] == args.name), None)
                _json(_status(found) if found else {"name": args.name, "state": "absent", "alive": False})
            else:
                _json([_status(r) for r in records])
        elif args.subcommand == "inspect":
            paths = paths_for(args.name); meta = load_meta(paths); status = _status(meta)
            status["resources"] = _resource_metrics(meta, paths)
            if status["alive"] and meta.get("signature"):
                for key_name, command in (("monitors", ["monitors"]), ("active_window", ["activewindow"]),
                                          ("cursor", ["cursorpos"])):
                    try:
                        status[key_name] = _hypr_json(args.name, command)
                    except RealmError as exc:
                        status[key_name] = {"error": str(exc)}
            _json(status)
        elif args.subcommand == "run":
            command = args.command[1:] if args.command and args.command[0] == "--" else args.command
            result = run_command(args.name, command, workspace=args.workspace,
                                 readonly_workspace=args.readonly_workspace, detach=args.detach,
                                 compositor_child=args.compositor_child,
                                 memory_max=args.memory_max, cpu_quota=args.cpu_quota,
                                 tasks_max=args.tasks_max)
            _json(result)
            return int(result.get("exit_code", 0))
        elif args.subcommand == "screenshot":
            _json({"path": str(_screenshot(args.name, args.output, args.monitor))})
        elif args.subcommand == "click":
            _json(vinput.click(paths_for(args.name), args.x, args.y, args.button, args.count))
        elif args.subcommand == "move":
            _json(vinput.move(paths_for(args.name), args.x, args.y))
        elif args.subcommand == "drag":
            _json(vinput.drag(paths_for(args.name), args.x1, args.y1, args.x2, args.y2, args.button))
        elif args.subcommand == "key":
            _json(vinput.key(paths_for(args.name), args.chord))
        elif args.subcommand == "type":
            _json(vinput.type_text(paths_for(args.name), args.text, args.delay_ms))
        elif args.subcommand == "scroll":
            _json(vinput.scroll(paths_for(args.name), args.x, args.y, args.dx, args.dy))
        elif args.subcommand == "windows":
            _json(_hypr_json(args.name, ["clients"]))
        elif args.subcommand == "logs":
            if args.tail < 1 or args.tail > 10000:
                raise RealmError("--tail debe estar entre 1 y 10000")
            paths = paths_for(args.name)
            for label, path in (("supervisor", paths.log), ("Hyprland", paths.compositor_log)):
                try:
                    lines = read_untrusted(path).splitlines()[-args.tail:]
                except OSError:
                    lines = []
                print(f"== {label} ==")
                print("\n".join(lines))
        elif args.subcommand == "doctor":
            _json(_doctor())
        elif args.subcommand == "observe":
            _json(_observe(args))
        elif args.subcommand == "profile":
            _json(_profile(args))
        elif args.subcommand == "simulate":
            _json(_simulate(args))
        return 0
    except (RealmError, OSError, subprocess.SubprocessError, ValueError) as exc:
        print(f"agent-realm: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
