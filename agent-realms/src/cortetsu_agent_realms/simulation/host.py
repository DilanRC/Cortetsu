"""Host side of `agent-realm simulate`: start, control and stop the in-realm simulator.

Stdlib only. Everything that touches the simulated services runs inside the realm
sandbox; the host only spawns sandboxed processes and reads their bounded JSON output.
"""
from __future__ import annotations

import json
import subprocess
import time
from typing import Any

from .. import runtime
from ..paths import RealmError, paths_for
from ..process import app_groups, lifecycle_lock, load_meta, process_alive
from .scenario import EVENTS, ScenarioError, load_scenario

DAEMON_MODULE = "cortetsu_agent_realms.simulation.daemon"
CTL = ["/usr/bin/python3", "-m", "cortetsu_agent_realms.simulation.ctl"]
MAX_OUTPUT = 1024 * 1024


def _live_meta(name: str) -> dict[str, Any]:
    meta = load_meta(paths_for(name))
    if not process_alive(meta) or meta.get("state") != "running":
        raise RealmError(f"la sesión {name!r} no está activa")
    return meta


def _daemon_records(name: str) -> list[dict[str, Any]]:
    return [app for app in app_groups(paths_for(name))
            if isinstance(app.get("command"), list) and DAEMON_MODULE in app["command"]]


def call(name: str, method: str, *args: str, timeout: float = 20) -> dict[str, Any]:
    """Run the control client inside the realm sandbox and return its parsed reply."""
    paths = paths_for(name)
    meta = _live_meta(name)
    argv = runtime.realm_bwrap(paths, meta, die_with_parent=True, mount_project=True) + CTL + [method, *args]
    try:
        result = subprocess.run(argv, capture_output=True, timeout=timeout, env=runtime._manager_env())
    except subprocess.TimeoutExpired as exc:
        raise RealmError("el simulador no respondió a tiempo") from exc
    try:
        reply = json.loads(result.stdout[:MAX_OUTPUT])  # produced in the realm: untrusted
    except ValueError as exc:
        raise RealmError("respuesta ilegible del simulador") from exc
    if not isinstance(reply, dict):
        raise RealmError("respuesta inválida del simulador")
    if "error" in reply:
        raise RealmError(f"simulador: {str(reply['error'])[:500]}")
    return reply


def running(name: str) -> bool:
    return bool(_daemon_records(name))


def start(name: str, scenario: str) -> dict[str, Any]:
    load_scenario(scenario)  # validate on the host before touching the realm
    with lifecycle_lock(paths_for(name)):
        if running(name):
            return call(name, "Apply", scenario)
        _live_meta(name)
        launched = runtime.run(name, ["/usr/bin/python3", "-m", DAEMON_MODULE, "--scenario", scenario],
                               detach=True, mount_project=True)
    deadline = time.monotonic() + 15
    last_error: Exception | None = None
    while time.monotonic() < deadline:
        try:
            return {"started": True, "app_id": launched["pid"], **call(name, "State")}
        except RealmError as exc:
            last_error = exc
            if not running(name):
                raise RealmError(f"el simulador terminó al iniciar: {exc}") from exc
            time.sleep(0.2)
    stop(name)
    raise RealmError(f"el simulador no quedó listo: {last_error}")


def stop(name: str) -> dict[str, Any]:
    stopped = [runtime.stop_app(name, record["pid"]) for record in _daemon_records(name)]
    return {"name": name, "simulation": "stopped", "stopped": len(stopped)}


def status(name: str) -> dict[str, Any]:
    if not running(name):
        return {"name": name, "simulation": "absent"}
    return {"name": name, "simulation": "running", **call(name, "State")}


def control(name: str, *, assignments: list[str] | None = None, event: str | None = None,
            reset: bool = False) -> dict[str, Any]:
    if not running(name):
        raise RealmError("no hay simulación activa; inicia una con --scenario")
    if assignments:
        return call(name, "Set", *assignments)
    if event:
        return call(name, "Event", event)
    if reset:
        return call(name, "Reset")
    raise ScenarioError(f"nada que hacer; usa --set, --event ({', '.join(EVENTS)}) o --reset")
