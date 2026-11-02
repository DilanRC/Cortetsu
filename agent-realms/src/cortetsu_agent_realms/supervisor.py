from __future__ import annotations

import argparse
import json
import os
import select
import signal
import stat
import subprocess
import sys
import time
from typing import BinaryIO
from pathlib import Path
from typing import Any

from .process import REPORT_NAME


stopping = False


def _request_stop(signum: int, _frame: object) -> None:
    global stopping
    stopping = True


def _atomic_json(path: Path, value: dict[str, Any]) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n")
    tmp.chmod(0o600)
    os.replace(tmp, path)


def _wayland_display(runtime: Path) -> str | None:
    for candidate in sorted(runtime.glob("wayland-*")):
        try:
            if stat.S_ISSOCK(candidate.stat().st_mode):
                return candidate.name
        except OSError:
            continue
    return None


def _signature(runtime: Path) -> str | None:
    for lock in sorted((runtime / "hypr").glob("*/hyprland.lock")):
        return lock.parent.name
    return None


def _terminate(proc: subprocess.Popen[bytes] | None, timeout: float = 4) -> None:
    if proc is None or proc.poll() is not None:
        return
    try:
        proc.terminate()
        proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def _launch_virtual_pointer(command: str, env: dict[str, str], log_path: Path,
                            timeout: float) -> tuple[subprocess.Popen[bytes], BinaryIO]:
    log_handle = log_path.open("ab", buffering=0)
    try:
        proc = subprocess.Popen([command, "keep"], stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                stderr=log_handle, env=env, close_fds=True)
    except BaseException:
        log_handle.close()
        raise
    try:
        ready, _, _ = select.select([proc.stdout], [], [], timeout)
        response = proc.stdout.readline() if ready and proc.stdout else b""
    except BaseException:
        _terminate(proc)
        if proc.stdout is not None:
            proc.stdout.close()
        log_handle.close()
        raise
    if response == b"READY\n":
        return proc, log_handle
    details = log_path.read_text(errors="replace")[-3000:]
    if proc.poll() is not None:
        details = f"cliente terminó con código {proc.returncode}; {details}"
    _terminate(proc)
    if proc.stdout is not None:
        proc.stdout.close()
    log_handle.close()
    raise RuntimeError(f"el puntero virtual persistente no confirmó READY: {details.strip()}")


def _stop_virtual_pointer(proc: subprocess.Popen[bytes] | None) -> None:
    _terminate(proc)
    if proc is not None and proc.stdout is not None:
        proc.stdout.close()


def _check_virtual_pointer(proc: subprocess.Popen[bytes]) -> None:
    code = proc.poll()
    if code is not None:
        raise RuntimeError(f"el puntero virtual terminó mientras Hyprland seguía activo, código {code}")


def supervise(args: argparse.Namespace) -> int:
    global stopping
    signal.signal(signal.SIGTERM, _request_stop)
    signal.signal(signal.SIGINT, _request_stop)
    runtime = Path(args.runtime_dir)
    parent_runtime = Path(args.parent_runtime_dir)
    state = Path(args.state_dir)
    runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent_runtime.mkdir(mode=0o700, parents=True, exist_ok=True)
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Untrusted report: realm processes share this mount. The host validates
    # it and keeps its own control record outside the sandbox.
    report_path = state / REPORT_NAME
    record: dict = {"schema": 1, "name": args.name}
    compositor_log = state / "hyprland.log"
    parent_log = state / "weston.log"
    pointer_log = state / "virtual-pointer.log"
    parent_socket = parent_runtime / "wayland-parent"
    bus_address = f"unix:path={runtime}/bus"
    bus_socket = runtime / "bus"
    bus_socket.unlink(missing_ok=True)
    for log_path in (compositor_log, parent_log, pointer_log):
        # A previous realm process may have planted a FIFO or symlink here.
        if log_path.is_symlink() or (log_path.exists() and not log_path.is_file()):
            log_path.unlink()
    bus_log = compositor_log.open("ab", buffering=0)
    weston_log = parent_log.open("ab", buffering=0)
    bus = None
    weston = None
    compositor = None
    virtual_pointer: subprocess.Popen[bytes] | None = None
    pointer_log_handle = None
    env = os.environ.copy()
    env["DBUS_SESSION_BUS_ADDRESS"] = bus_address
    env["DBUS_SYSTEM_BUS_ADDRESS"] = f"unix:path={runtime}/system_bus_socket"
    env.pop("WAYLAND_DISPLAY", None)
    env.pop("HYPRLAND_INSTANCE_SIGNATURE", None)
    env.pop("DISPLAY", None)
    try:
        bus = subprocess.Popen(["/usr/bin/dbus-daemon", "--session", "--nofork", "--nopidfile",
                                "--nosyslog", "--address", bus_address],
                               stdin=subprocess.DEVNULL, stdout=bus_log, stderr=subprocess.STDOUT,
                               close_fds=True)
        deadline = time.monotonic() + 5
        while not bus_socket.exists() and time.monotonic() < deadline:
            if bus.poll() is not None:
                raise RuntimeError(f"D-Bus privado terminó con código {bus.returncode}")
            time.sleep(0.025)
        if not bus_socket.exists():
            raise RuntimeError("D-Bus privado no creó el socket en XDG_RUNTIME_DIR")

        parent_env = env.copy()
        parent_env["XDG_RUNTIME_DIR"] = str(parent_runtime)
        parent_env.pop("WAYLAND_DISPLAY", None)
        parent_env["LD_PRELOAD"] = args.version_shim
        weston = subprocess.Popen([args.weston, "--backend=headless", "--renderer=gl",
                                   "--width", str(args.width), "--height", str(args.height),
                                   "--socket=wayland-parent", "--idle-time=0", "--no-config"],
                                  stdin=subprocess.DEVNULL, stdout=weston_log, stderr=weston_log,
                                  env=parent_env, close_fds=True)
        deadline = time.monotonic() + args.start_timeout
        while not parent_socket.exists() and time.monotonic() < deadline and not stopping:
            if weston.poll() is not None:
                tail = parent_log.read_text(errors="replace")[-5000:]
                raise RuntimeError(f"Weston GL terminó durante el inicio, código {weston.returncode}:\n{tail}")
            time.sleep(0.05)
        if not parent_socket.exists():
            raise RuntimeError("Weston GL no publicó el socket Wayland padre privado")
        if not stat.S_ISSOCK(parent_socket.stat().st_mode):
            raise RuntimeError("la ruta del socket padre existe, pero no es un socket Unix")

        compositor_env = env.copy()
        compositor_env["XDG_RUNTIME_DIR"] = str(runtime)
        compositor_env["WAYLAND_DISPLAY"] = str(parent_socket)
        compositor_env["AQ_BACKEND"] = "wayland"
        compositor_env.pop("LD_PRELOAD", None)
        compositor = subprocess.Popen([args.compositor, "-c", args.config],
                                      stdin=subprocess.DEVNULL, stdout=bus_log, stderr=subprocess.STDOUT,
                                      env=compositor_env, close_fds=True)
        deadline = time.monotonic() + args.start_timeout
        sig = display = None
        while time.monotonic() < deadline and not stopping:
            if weston.poll() is not None:
                raise RuntimeError(f"Weston GL terminó antes de Hyprland, código {weston.returncode}")
            if compositor.poll() is not None:
                raise RuntimeError(f"Hyprland terminó durante el inicio, código {compositor.returncode}")
            sig = _signature(runtime)
            display = _wayland_display(runtime)
            if sig and display:
                break
            time.sleep(0.05)
        if not sig or not display:
            raise RuntimeError("Hyprland no publicó firma IPC y socket Wayland privados")

        pointer_env = env.copy()
        pointer_env["XDG_RUNTIME_DIR"] = str(runtime)
        pointer_env["WAYLAND_DISPLAY"] = display
        pointer_env["HYPRLAND_INSTANCE_SIGNATURE"] = sig
        virtual_pointer, pointer_log_handle = _launch_virtual_pointer(
            args.input_client, pointer_env, pointer_log, args.start_timeout)

        # Publish the private endpoints as soon as they exist.  The manager owns
        # IPC readiness and output creation; waiting for a monitor here would
        # race its startup deadline and duplicate output configuration.
        record.update({
            "state": "starting",
            "signature": sig,
            "wayland_display": display,
            "dbus_session_bus_address": bus_address,
            "parent_runtime_directory": str(parent_runtime),
            "parent_wayland_display": str(parent_socket),
            "parent_compositor": args.weston,
            "parent_backend": "Weston headless GL, sin seat físico; shim agrega wl_seat sin capacidades",
            "parent_pid_namespace_pid": weston.pid,
            "pid_namespace_supervisor_pid": os.getpid(),
            "compositor_pid_namespace_pid": compositor.pid,
            "virtual_pointer_device_pid": virtual_pointer.pid,
        })
        _atomic_json(report_path, record)

        while not stopping and compositor.poll() is None:
            if weston.poll() is not None:
                raise RuntimeError(f"Weston GL terminó mientras Hyprland seguía activo, código {weston.returncode}")
            if bus.poll() is not None:
                raise RuntimeError(f"D-Bus privado terminó mientras Hyprland seguía activo, código {bus.returncode}")
            _check_virtual_pointer(virtual_pointer)
            time.sleep(0.2)
        code = compositor.poll()
        record["state"] = "stopped" if stopping else "crashed"
        record["compositor_exit_code"] = code
        record["stopped_at"] = time.time()
        _atomic_json(report_path, record)
        return 0 if stopping else (int(code) if code is not None else 1)
    except Exception as exc:
        record["state"] = "failed" if not stopping else "stopped"
        record["error"] = str(exc)
        record["failed_at"] = time.time()
        _atomic_json(report_path, record)
        print(f"agent-realm supervisor: {exc}", file=sys.stderr, flush=True)
        return 1
    finally:
        _stop_virtual_pointer(virtual_pointer)
        _terminate(compositor)
        _terminate(weston)
        _terminate(bus)
        if pointer_log_handle is not None:
            pointer_log_handle.close()
        bus_log.close()
        weston_log.close()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--compositor", required=True)
    parser.add_argument("--config", required=True)
    parser.add_argument("--state-dir", required=True)
    parser.add_argument("--runtime-dir", required=True)
    parser.add_argument("--parent-runtime-dir", required=True)
    parser.add_argument("--weston", required=True)
    parser.add_argument("--version-shim", required=True)
    parser.add_argument("--input-client", required=True)
    parser.add_argument("--name", required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--start-timeout", type=float, default=25)
    return supervise(parser.parse_args())


if __name__ == "__main__":
    raise SystemExit(main())
