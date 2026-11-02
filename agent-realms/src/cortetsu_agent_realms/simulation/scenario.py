"""Versioned scenario files and the validated state model shared by host and realm.

A scenario is `{"schema": 1, "name": ..., "description": ..., "state": {partial}}`.
Its partial state is merged over BASELINE and the result must match SPEC exactly:
unknown keys, wrong types and out-of-range values are rejected, so a typo never
silently becomes a default. Stdlib only; runs on the host and inside the realm.
"""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path
from typing import Any

SCHEMA = 1
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,47}$")
NODE_RE = re.compile(r"^[A-Za-z0-9_.-]{1,64}$")
MAC_RE = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$")


EVENTS = ("wifi-scan", "bt-discover", "pipewire-restart")


class ScenarioError(ValueError):
    pass


def _ap(ssid: str, strength: int, secured: bool, frequency: int) -> dict[str, Any]:
    return {"ssid": ssid, "strength": strength, "secured": secured, "frequency": frequency}


def _bt(address: str, name: str, icon: str, *, paired: bool = False, connected: bool = False,
        battery: int | None = None) -> dict[str, Any]:
    return {"address": address, "name": name, "icon": icon, "paired": paired, "trusted": paired,
            "connected": connected, "battery": battery}


BASELINE: dict[str, Any] = {
    "upower": {
        "available": True,
        "battery": {"present": True, "percentage": 80.0, "state": "discharging", "time_to_empty": 14400,
                    "time_to_full": 0, "energy_full": 57.0, "capacity": 96.0},
        "line_power": {"present": True, "online": False},
    },
    "power_profiles": {"available": True, "active": "balanced",
                       "profiles": ["power-saver", "balanced", "performance"],
                       "degraded": "", "reject_changes": False},
    "network": {
        "available": True, "wireless_enabled": True, "wireless_hardware_enabled": True, "connectivity": "full",
        "wifi": {"present": True, "connected": "CortetsuLab", "fail_connect": False,
                 "access_points": [_ap("CortetsuLab", 82, True, 5180), _ap("Cafe Libre", 47, False, 2437)],
                 "nearby": [_ap("Biblioteca UNA", 35, True, 2412)]},
        "ethernet": {"present": False, "connected": False, "speed": 1000},
    },
    "bluetooth": {
        "available": True, "fail_operations": False,
        "adapter": {"present": True, "powered": True, "discovering": False, "discoverable": False,
                    "pairable": True, "alias": "realm-bluetooth"},
        "devices": [_bt("AA:BB:CC:00:00:01", "Auriculares simulados", "audio-headphones", paired=True,
                        battery=70)],
        "nearby": [_bt("AA:BB:CC:00:00:02", "Teclado simulado", "input-keyboard")],
    },
    "audio": {
        "available": True, "restarting": False, "playback": False,
        "sinks": [{"name": "sim_speakers", "description": "Altavoces simulados", "volume": 0.6, "mute": False},
                  {"name": "sim_headphones", "description": "Auriculares simulados", "volume": 0.4,
                   "mute": False}],
        "sources": [{"name": "sim_mic", "description": "Micrófono simulado", "volume": 0.8, "mute": False}],
        "default_sink": "sim_speakers", "default_source": "sim_mic",
    },
}

# Type spec: a type, a (type, check) pair, a nested dict, or a one-element list of an item spec.
_PCT = (float, lambda v: 0 <= v <= 100)
_UNIT = (float, lambda v: 0 <= v <= 1.5)
_AP = {"ssid": (str, lambda v: 0 < len(v.encode()) <= 32), "strength": (int, lambda v: 0 <= v <= 100),
       "secured": bool, "frequency": (int, lambda v: 2400 <= v <= 7200)}
_BT = {"address": (str, MAC_RE.fullmatch), "name": (str, lambda v: 0 < len(v) <= 64),
       "icon": (str, lambda v: 0 < len(v) <= 64), "paired": bool, "trusted": bool, "connected": bool,
       "battery": (int, lambda v: 0 <= v <= 100, "nullable")}
# Descriptions travel inside PipeWire SPA-JSON, so quotes, braces and backslashes are refused.
_NODE = {"name": (str, NODE_RE.fullmatch), "description": (str, re.compile(r'^[^"{}\\\[\]=\n]{1,80}$').fullmatch),
         "volume": _UNIT, "mute": bool}
SPEC: dict[str, Any] = {
    "upower": {
        "available": bool,
        "battery": {"present": bool, "percentage": _PCT,
                    "state": (str, {"charging", "discharging", "empty", "fully-charged",
                                    "pending-charge", "pending-discharge", "unknown"}.__contains__),
                    "time_to_empty": (int, lambda v: 0 <= v <= 360000),
                    "time_to_full": (int, lambda v: 0 <= v <= 360000),
                    "energy_full": (float, lambda v: 0 < v <= 500), "capacity": _PCT},
        "line_power": {"present": bool, "online": bool},
    },
    "power_profiles": {"available": bool,
                       "active": (str, {"power-saver", "balanced", "performance"}.__contains__),
                       "profiles": [(str, {"power-saver", "balanced", "performance"}.__contains__)],
                       "degraded": (str, {"", "lap-detected", "high-operating-temperature"}.__contains__),
                       "reject_changes": bool},
    "network": {
        "available": bool, "wireless_enabled": bool, "wireless_hardware_enabled": bool,
        "connectivity": (str, {"unknown", "none", "portal", "limited", "full"}.__contains__),
        "wifi": {"present": bool, "connected": (str, lambda v: 0 < len(v) <= 32, "nullable"),
                 "fail_connect": bool, "access_points": [_AP], "nearby": [_AP]},
        "ethernet": {"present": bool, "connected": bool, "speed": (int, lambda v: 0 < v <= 100000)},
    },
    "bluetooth": {
        "available": bool, "fail_operations": bool,
        "adapter": {"present": bool, "powered": bool, "discovering": bool, "discoverable": bool,
                    "pairable": bool, "alias": (str, lambda v: 0 < len(v) <= 64)},
        "devices": [_BT], "nearby": [_BT],
    },
    "audio": {
        "available": bool, "restarting": bool, "playback": bool, "sinks": [_NODE], "sources": [_NODE],
        "default_sink": (str, NODE_RE.fullmatch, "nullable"),
        "default_source": (str, NODE_RE.fullmatch, "nullable"),
    },
}


def _check(value: Any, spec: Any, where: str) -> Any:
    if isinstance(spec, dict):
        if not isinstance(value, dict):
            raise ScenarioError(f"{where}: se esperaba un objeto")
        unknown = set(value) - set(spec)
        missing = set(spec) - set(value)
        if unknown or missing:
            raise ScenarioError(f"{where}: claves desconocidas {sorted(unknown)} o ausentes {sorted(missing)}")
        return {key: _check(value[key], spec[key], f"{where}.{key}") for key in spec}
    if isinstance(spec, list):
        if not isinstance(value, list) or len(value) > 32:
            raise ScenarioError(f"{where}: se esperaba una lista de hasta 32 elementos")
        return [_check(item, spec[0], f"{where}[{i}]") for i, item in enumerate(value)]
    kind, check, nullable = (spec, None, False) if isinstance(spec, type) else \
        (spec[0], spec[1], len(spec) > 2)
    if value is None and nullable:
        return None
    if kind is float and type(value) is int:
        value = float(value)
    if type(value) is not kind or (check is not None and not check(value)):
        raise ScenarioError(f"{where}: valor no admitido {value!r}")
    return value


def merge(base: dict[str, Any], partial: dict[str, Any], where: str = "state") -> dict[str, Any]:
    if not isinstance(partial, dict):
        raise ScenarioError(f"{where}: se esperaba un objeto")
    result = copy.deepcopy(base)
    for key, value in partial.items():
        if key not in result:
            raise ScenarioError(f"{where}.{key}: clave desconocida")
        if isinstance(result[key], dict) and isinstance(value, dict):
            result[key] = merge(result[key], value, f"{where}.{key}")
        else:
            result[key] = copy.deepcopy(value)
    return result


def validate(state: Any) -> dict[str, Any]:
    state = _check(state, SPEC, "state")
    _check_consistency(state)
    return state


def _check_consistency(state: dict[str, Any]) -> None:
    pp = state["power_profiles"]
    if pp["active"] not in pp["profiles"]:
        raise ScenarioError("power_profiles.active debe estar en profiles")
    wifi = state["network"]["wifi"]
    if wifi["connected"] is not None and wifi["connected"] not in {ap["ssid"] for ap in wifi["access_points"]}:
        raise ScenarioError("network.wifi.connected debe ser el ssid de un punto de acceso visible")
    for key in ("devices", "nearby"):
        addresses = [d["address"] for d in state["bluetooth"][key]]
        if len(addresses) != len(set(addresses)):
            raise ScenarioError(f"bluetooth.{key} repite direcciones")
    audio = state["audio"]
    for kind, default in (("sinks", "default_sink"), ("sources", "default_source")):
        names = [n["name"] for n in audio[kind]]
        if len(names) != len(set(names)):
            raise ScenarioError(f"audio.{kind} repite nombres")
        if audio[default] is not None and audio[default] not in names:
            raise ScenarioError(f"audio.{default} debe nombrar un nodo de audio.{kind}")


def scenarios_dir() -> Path:
    return Path(__file__).resolve().parents[3] / "scenarios"


def load_scenario(name: str, directory: Path | None = None) -> dict[str, Any]:
    if not NAME_RE.fullmatch(name):
        raise ScenarioError("nombre de escenario inválido")
    path = (directory or scenarios_dir()) / f"{name}.json"
    try:
        data = json.loads(path.read_text())
    except FileNotFoundError as exc:
        raise ScenarioError(f"no existe el escenario {name!r}") from exc
    except (OSError, json.JSONDecodeError) as exc:
        raise ScenarioError(f"escenario {name!r} ilegible: {exc}") from exc
    if not isinstance(data, dict) or set(data) != {"schema", "name", "description", "state"}:
        raise ScenarioError(f"{name}: se esperaba schema, name, description y state")
    if data["schema"] != SCHEMA or data["name"] != name or not isinstance(data["description"], str):
        raise ScenarioError(f"{name}: schema {SCHEMA} y name igual al nombre del archivo")
    return {"name": name, "description": data["description"],
            "state": validate(merge(BASELINE, data["state"]))}


def list_scenarios(directory: Path | None = None) -> list[dict[str, str]]:
    result = []
    for path in sorted((directory or scenarios_dir()).glob("*.json")):
        scenario = load_scenario(path.stem, directory)
        result.append({"name": scenario["name"], "description": scenario["description"]})
    return result


def apply_assignment(state: dict[str, Any], assignment: str) -> dict[str, Any]:
    """`a.b.c=<json>` (or a bare string) applied to a copy of state, then validated."""
    path, sep, raw = assignment.partition("=")
    if not sep or not re.fullmatch(r"[a-z_]+(\.([a-z_]+|[0-9]{1,2}))*", path):
        raise ScenarioError("usa ruta=valor, por ejemplo upower.battery.percentage=12")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        value = raw
    result = copy.deepcopy(state)
    *parents, last = path.split(".")
    target: Any = result
    try:
        for key in parents:
            target = target[int(key)] if isinstance(target, list) else target[key]
        if isinstance(target, list):
            target[int(last)] = value
        elif last in target:
            target[last] = value
        else:
            raise KeyError(last)
    except (KeyError, IndexError, ValueError, TypeError) as exc:
        raise ScenarioError(f"ruta inexistente: {path}") from exc
    return validate(result)
