"""Realm operations for automation clients, bound to one profile.

Independent of any MCP SDK so it can be tested with the standard library. Every
operation targets `profile.realm`; nothing accepts a realm name from the caller.
"""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import subprocess
from collections import OrderedDict
from typing import Any, Callable

from . import capture as cap
from . import input as vinput
from . import runtime
from .auth import Capability
from .paths import RealmError, paths_for
from .process import app_groups, load_meta, process_alive, read_untrusted, supervisor_present
from .profiles import Profile

_ADDRESS_RE = re.compile(r"^0x[0-9a-f]{1,16}$")
MAX_FRAMES = 16
HEALTHY = "running"


class AgentError(RealmError):
    """A failure with a stable code and a next step the client can act on."""

    def __init__(self, code: str, message: str, hint: str | None = None):
        super().__init__(message)
        self.code = code
        self.hint = hint

    def as_dict(self) -> dict[str, Any]:
        error = {"code": self.code, "message": str(self)}
        if self.hint:
            error["hint"] = self.hint
        return {"error": error}


def classify(error: Exception) -> AgentError:
    if isinstance(error, AgentError):
        return error
    if isinstance(error, subprocess.TimeoutExpired):
        return AgentError("backend_timeout", f"el backend tardó demasiado: {error.cmd[0] if error.cmd else ''}")
    if isinstance(error, (RealmError, OSError, subprocess.SubprocessError, ValueError)):
        return AgentError("backend_error", str(error)[:2000])
    return AgentError("internal_error", type(error).__name__)


def _geometry(mon: cap.Monitor) -> tuple[Any, ...]:
    return mon.name, mon.x, mon.y, mon.width, mon.height, mon.scale


class RealmAgent:
    def __init__(self, profile: Profile, *, start_fn: Callable[..., dict[str, Any]] | None = None):
        self.profile = profile
        self.realm = profile.realm
        self._start = start_fn or runtime.start
        self._frames: OrderedDict[str, cap.Frame] = OrderedDict()
        self.started_here = False

    # -- capabilities and lifecycle -------------------------------------------------

    def require(self, capability: Capability) -> None:
        if not self.profile.allows(capability):
            raise AgentError("forbidden", f"el perfil {self.profile.name!r} no concede {capability.value}",
                             "añade la capacidad al perfil con `agent-realm profile set`")

    def lifecycle(self) -> dict[str, Any]:
        """Current state of the bound realm, from host-owned metadata and systemd only."""
        paths = paths_for(self.realm)
        try:
            meta = load_meta(paths)
        except RealmError as exc:
            if "no existe" in str(exc):
                return {"state": "absent", "alive": False}
            return {"state": "corrupt", "alive": False, "detail": str(exc)}
        alive = process_alive(meta)
        state = meta.get("state")
        result: dict[str, Any] = {"state": state, "alive": alive,
                                  "config_format": meta.get("config_format", "hyprlang")}
        if not alive and state in {"running", "paused", "starting", "degraded"}:
            result["state"] = "stale"
        elif alive and state == HEALTHY:
            unit = meta.get("systemd_scope_unit")
            if isinstance(unit, str) and not supervisor_present(unit):
                result["state"] = "degraded"
            else:
                try:
                    result["ipc_reachable"] = bool(cap.monitors(self.realm))
                except RealmError:
                    result["ipc_reachable"] = False
                    result["state"] = "degraded"
        return result

    def ensure_ready(self) -> dict[str, Any]:
        state = self.lifecycle()
        if state["state"] == HEALTHY:
            return state
        if state["state"] in {"absent", "recovered"} and self.profile.autostart:
            return self.start()
        hints = {
            "absent": ("realm_absent", "el realm no existe y el perfil no lo inicia solo", "llama a realm_start"),
            "stopped": ("realm_stopped", "el realm se detuvo explícitamente; no se reinicia solo",
                        "llama a realm_start si quieres reanudarlo"),
            "paused": ("realm_paused", "el realm está pausado", "agent-realm resume <realm>"),
            "degraded": ("realm_degraded", "el compositor responde mal o perdió su supervisor",
                         "llama a realm_stop y después a realm_start"),
        }
        code, message, hint = hints.get(state["state"], (
            "realm_unavailable", f"el realm está en estado {state['state']!r}", "llama a realm_start"))
        raise AgentError(code, message, hint)

    def start(self) -> dict[str, Any]:
        state = self.lifecycle()
        if state["state"] == HEALTHY:
            return {**state, "reused": True}
        if state["alive"]:
            raise AgentError("realm_degraded", f"el realm sigue vivo en estado {state['state']!r}",
                             "llama a realm_stop y después a realm_start")
        if state["state"] in {"stale", "failed", "crashed", "cleanup_failed", "corrupt", "transition-error"}:
            runtime.recover(self.realm)
        options = dict(self.profile.start)
        try:
            self._start(self.realm, ephemeral=self.profile.lifecycle == "ephemeral", **options)
        except RealmError as exc:
            if "ya está activa" not in str(exc):
                raise
            # Another client started it between our check and the lifecycle lock.
            state = self.lifecycle()
            if state["state"] != HEALTHY:
                raise
            return {**state, "reused": True}
        self.started_here = True
        return {**self.lifecycle(), "reused": False}

    def stop(self) -> dict[str, Any]:
        self._frames.clear()
        return runtime.stop(self.realm)

    # -- observation -----------------------------------------------------------------

    def status(self) -> dict[str, Any]:
        result = {"binding": self.profile.describe(), **self.lifecycle()}
        if result["state"] == HEALTHY:
            try:
                result["monitors"] = [m.__dict__ for m in cap.monitors(self.realm)]
                result["focused_window"] = self._active_address()
                result["apps"] = len(app_groups(paths_for(self.realm)))
            except RealmError as exc:
                result["warning"] = str(exc)
        return result

    def screenshot(self, monitor: str | None = None, max_width: int = 1280) -> cap.Frame:
        self.ensure_ready()
        mon = cap.pick_monitor(cap.monitors(self.realm), monitor)
        scale = min(mon.scale, max_width / mon.logical_width)
        frame = cap.capture(self.realm, monitor=mon.name, scale=scale)
        self._frames[frame.frame_id] = frame
        while len(self._frames) > MAX_FRAMES:
            self._frames.popitem(last=False)
        return frame

    def fingerprint(self, monitor: str | None = None) -> str:
        """Cheap visual hash: raw pixels of a quarter-scale capture."""
        frame = cap.capture(self.realm, monitor=monitor, scale=0.25, image_format="ppm")
        return hashlib.sha256(frame.data).hexdigest()

    def logs(self, source: str = "all", tail: int = 100) -> dict[str, list[str]]:
        if not 1 <= tail <= 500:
            raise AgentError("invalid_argument", "tail debe estar entre 1 y 500")
        paths = paths_for(self.realm)
        sources = {"supervisor": paths.log, "hyprland": paths.compositor_log}
        if source != "all" and source not in sources:
            raise AgentError("invalid_argument", "source debe ser supervisor, hyprland o all")
        result = {}
        for label, path in sources.items():
            if source in {"all", label}:
                try:
                    result[label] = read_untrusted(path).splitlines()[-tail:]
                except OSError:
                    result[label] = []
        return result

    def diagnose(self) -> dict[str, Any]:
        from .cli import _resource_metrics
        from .observer import control_request
        paths = paths_for(self.realm)
        result: dict[str, Any] = {"status": self.status()}
        result["tools"] = {name: bool(shutil.which(name, path="/usr/bin:/bin"))
                           for name in ("Hyprland", "hyprctl", "grim", "wtype", "bwrap", "systemd-run")}
        try:
            result["resources"] = _resource_metrics(load_meta(paths), paths)
        except RealmError as exc:
            result["resources"] = {"error": str(exc)}
        try:
            result["observer"] = control_request(self.realm, "status") or {"observer": "absent"}
        except RealmError as exc:
            result["observer"] = {"error": str(exc)}
        result["recent_logs"] = self.logs("all", 20)
        return result

    # -- windows and apps --------------------------------------------------------------

    def _hypr_json(self, *command: str) -> Any:
        response = runtime.private_call(self.realm, ["-j", *command])
        if response.returncode != 0:
            raise AgentError("backend_error", response.stderr.strip() or "hyprctl falló")
        try:
            return json.loads(response.stdout)
        except json.JSONDecodeError as exc:
            raise AgentError("backend_error", f"hyprctl devolvió JSON inválido: {exc}") from exc

    def _active_address(self) -> str | None:
        active = self._hypr_json("activewindow")
        return active.get("address") if isinstance(active, dict) else None

    def windows(self) -> dict[str, Any]:
        self.ensure_ready()
        focused = self._active_address()
        windows = []
        for client in self._hypr_json("clients"):
            windows.append({"address": client.get("address"), "class": client.get("class"),
                            "title": client.get("title"), "pid": client.get("pid"),
                            "workspace": (client.get("workspace") or {}).get("name"),
                            "at": client.get("at"), "size": client.get("size"),
                            "focused": client.get("address") == focused})
        return {"focused_address": focused, "windows": windows}

    def _known_window(self, address: str) -> None:
        if not isinstance(address, str) or not _ADDRESS_RE.fullmatch(address):
            raise AgentError("invalid_argument", "address debe tener la forma 0x1a2b…")
        if address not in {w["address"] for w in self.windows()["windows"]}:
            raise AgentError("not_found", f"no hay una ventana {address} en el realm",
                             "consulta window_list")

    def _dispatch_window(self, action: str, address: str) -> None:
        # address is validated against _ADDRESS_RE, so it is safe inside a Lua literal.
        if self.lifecycle().get("config_format") == "lua":
            call = "hl.dsp.focus" if action == "focus" else "hl.dsp.window.close"
            argv = ["dispatch", f'{call}({{ window = "address:{address}" }})']
        else:
            argv = ["dispatch", "focuswindow" if action == "focus" else "closewindow", f"address:{address}"]
        response = runtime.private_call(self.realm, argv)
        if response.returncode != 0 or response.stdout.strip() not in {"ok", ""}:
            raise AgentError("backend_error", (response.stderr or response.stdout).strip() or "dispatch falló")

    def focus_window(self, address: str) -> dict[str, Any]:
        self._known_window(address)
        self._dispatch_window("focus", address)
        focused = self._active_address()
        return {"address": address, "focused": focused == address, "focused_address": focused}

    def close_window(self, address: str) -> dict[str, Any]:
        self._known_window(address)
        self._dispatch_window("close", address)
        return {"address": address, "close_requested": True}

    def launch(self, argv: list[str], compositor_child: bool = False) -> dict[str, Any]:
        if not argv or len(argv) > 64 or not all(isinstance(a, str) and a and "\0" not in a and len(a) <= 4096
                                                  for a in argv):
            raise AgentError("invalid_argument", "argv debe tener entre 1 y 64 cadenas no vacías")
        self.ensure_ready()
        result = runtime.run(self.realm, argv, detach=True, compositor_child=compositor_child)
        if compositor_child:
            return {"app_id": None, "launch_mode": "compositor-child", "command": argv,
                    "note": "comparte el scope del compositor; ciérrala con window_close"}
        return {"app_id": result["pid"], "launch_mode": "scoped", "command": argv}

    def apps(self) -> list[dict[str, Any]]:
        self.ensure_ready()
        return [{"app_id": a.get("pid"), "command": a.get("command"), "started_at": a.get("started_at"),
                 "systemd_scope_unit": a.get("systemd_scope_unit")} for a in app_groups(paths_for(self.realm))]

    def close_app(self, app_id: int) -> dict[str, Any]:
        self.ensure_ready()
        return runtime.stop_app(self.realm, app_id)

    # -- simulated system services -----------------------------------------------------

    def services(self) -> dict[str, Any]:
        from .simulation import host
        self.ensure_ready()
        return host.status(self.realm)

    def simulate(self, action: str, *, scenario: str | None = None,
                 assignments: list[str] | None = None, event: str | None = None) -> dict[str, Any]:
        from .simulation import host
        self.ensure_ready()
        if action == "apply":
            if not scenario:
                raise AgentError("invalid_argument", "apply requiere scenario")
            return host.start(self.realm, scenario)
        if action == "set":
            if not assignments:
                raise AgentError("invalid_argument", "set requiere assignments como ruta=valor")
            return host.control(self.realm, assignments=assignments)
        if action == "event":
            return host.control(self.realm, event=event)
        if action == "reset":
            return host.control(self.realm, reset=True)
        if action == "stop":
            return host.stop(self.realm)
        raise AgentError("invalid_argument", "action debe ser apply, set, event, reset o stop")

    # -- input -------------------------------------------------------------------------

    def _to_desktop(self, x: float, y: float, frame_id: str | None) -> tuple[int, int]:
        monitors = cap.monitors(self.realm)
        if frame_id is not None:
            frame = self._frames.get(frame_id)
            if frame is None:
                raise AgentError("unknown_frame", f"frame {frame_id!r} desconocido o expirado",
                                 "toma una captura nueva con screenshot")
            meta = load_meta(paths_for(self.realm))
            if frame.session != cap.session_identity(meta) or \
                    _geometry(frame.monitor) not in {_geometry(m) for m in monitors}:
                raise AgentError("stale_frame", "el realm o su monitor cambiaron desde ese frame",
                                 "toma una captura nueva con screenshot")
            try:
                return frame.to_desktop(x, y)
            except RealmError as exc:
                raise AgentError("out_of_bounds", str(exc)) from exc
        for mon in monitors:
            if mon.x <= x < mon.x + mon.logical_width and mon.y <= y < mon.y + mon.logical_height:
                return int(x), int(y)
        raise AgentError("out_of_bounds", f"({x}, {y}) cae fuera de todos los monitores del realm",
                         "usa coordenadas de un frame con frame_id")

    def pointer(self, action: str, x: float, y: float, *, frame_id: str | None = None,
                x2: float | None = None, y2: float | None = None, button: str = "left",
                dx: int = 0, dy: int = 0) -> dict[str, Any]:
        self.ensure_ready()
        paths = paths_for(self.realm)
        if button not in {"left", "right", "middle"}:
            raise AgentError("invalid_argument", "button debe ser left, right o middle")
        px, py = self._to_desktop(x, y, frame_id)
        result: dict[str, Any] = {"action": action, "desktop": [px, py]}
        if action == "move":
            vinput.move(paths, px, py)
        elif action in {"click", "double_click"}:
            vinput.click(paths, px, py, button, 2 if action == "double_click" else 1)
        elif action == "drag":
            if x2 is None or y2 is None:
                raise AgentError("invalid_argument", "drag requiere x2 e y2")
            qx, qy = self._to_desktop(x2, y2, frame_id)
            vinput.drag(paths, px, py, qx, qy, button)
            result["desktop_end"] = [qx, qy]
        elif action == "scroll":
            if not (-10000 <= dx <= 10000 and -10000 <= dy <= 10000) or (dx == 0 and dy == 0):
                raise AgentError("invalid_argument", "scroll requiere dx o dy entre -10000 y 10000")
            vinput.scroll(paths, px, py, dx, dy)
        else:
            raise AgentError("invalid_argument", "action debe ser move, click, double_click, drag o scroll")
        return result

    def keyboard(self, action: str, value: str) -> dict[str, Any]:
        self.ensure_ready()
        paths = paths_for(self.realm)
        if not isinstance(value, str) or not value or len(value) > 4096:
            raise AgentError("invalid_argument", "value debe tener entre 1 y 4096 caracteres")
        if action == "type":
            return vinput.type_text(paths, value)
        if action == "key":
            return vinput.key(paths, value)
        raise AgentError("invalid_argument", "action debe ser key o type")
