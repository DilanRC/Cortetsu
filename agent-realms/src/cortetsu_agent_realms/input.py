from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path

from .paths import RealmError, RealmPaths
from .runtime import _realm_env, private_call


WTYPE_START_DELAY_MS = 50


def _screen(paths: RealmPaths) -> tuple[int, int, int, int]:
    result = private_call(paths.name, ["-j", "monitors"])
    if result.returncode != 0:
        raise RealmError("no se pudieron consultar los monitores del realm: " + result.stderr.strip())
    try:
        monitors = json.loads(result.stdout)
        if not monitors:
            raise ValueError("no hay monitores")
        min_x = min(int(m.get("x", 0)) for m in monitors)
        min_y = min(int(m.get("y", 0)) for m in monitors)
        max_x = max(int(m.get("x", 0)) + int(m.get("width", 0)) for m in monitors)
        max_y = max(int(m.get("y", 0)) + int(m.get("height", 0)) for m in monitors)
        if max_x <= min_x or max_y <= min_y:
            raise ValueError("geometría de monitor vacía")
        return min_x, min_y, max_x - min_x, max_y - min_y
    except (ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        raise RealmError(f"respuesta de monitores inválida: {exc}") from exc


def virtual_input_binary() -> Path:
    root = Path(__file__).resolve().parents[2]
    source = root / "src/realm_input.c"
    protocols = [root / "protocols/wlr-virtual-pointer-unstable-v1.xml",
                 root / "protocols/virtual-keyboard-unstable-v1.xml"]
    build_script = root / "scripts/build-virtual-input.sh"
    digest = hashlib.sha256()
    for path in (source, *protocols, build_script):
        digest.update(path.read_bytes())
    target = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache")) / \
        "cortetsu-agent-realms" / f"realm-input-{digest.hexdigest()[:16]}"
    if target.is_file() and os.access(target, os.X_OK):
        return target
    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    result = subprocess.run(["/bin/bash", str(build_script), str(target)],
                            capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RealmError("no se pudo compilar el cliente Wayland virtual; requiere wayland-scanner, "
                         "pkg-config, wayland-client y un compilador C: " + result.stderr.strip())
    return target


def _pointer(paths: RealmPaths, action: str, coordinates: list[int | str]) -> dict[str, object]:
    min_x, min_y, width, height = _screen(paths)
    binary = str(virtual_input_binary())
    # CLI coordinates follow Hyprland's virtual desktop space. The protocol uses a
    # zero-based extent, so translate the desktop bounding-box origin.
    if action == "move":
        x, y = map(int, coordinates[:2])
        args = [binary, action, str(x - min_x), str(y - min_y), str(width), str(height)]
    elif action == "click":
        x, y, button_name, count = coordinates
        args = [binary, action, str(int(x) - min_x), str(int(y) - min_y),
                str(width), str(height), str(button_name), str(count)]
    elif action == "drag":
        x1, y1, x2, y2, button_name = coordinates
        args = [binary, action, str(int(x1) - min_x), str(int(y1) - min_y),
                str(int(x2) - min_x), str(int(y2) - min_y), str(width), str(height),
                str(button_name)]
    elif action == "scroll":
        x, y, dx, dy = map(int, coordinates)
        args = [binary, action, str(x - min_x), str(y - min_y), str(width), str(height),
                str(dx), str(dy)]
    else:
        raise RealmError(f"acción de puntero no admitida: {action}")
    env = _realm_env(paths, _load(paths))
    before = time.monotonic()
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=15)
    elapsed_ms = (time.monotonic() - before) * 1000
    if result.returncode != 0:
        raise RealmError(result.stderr.strip() or f"cliente de entrada virtual terminó con {result.returncode}")
    return {"action": action, "elapsed_ms": round(elapsed_ms, 2), "coordinates": coordinates}


def _load(paths: RealmPaths) -> dict:
    from .process import load_meta
    return load_meta(paths)


def move(paths: RealmPaths, x: int, y: int) -> dict[str, object]:
    return _pointer(paths, "move", [x, y])


def click(paths: RealmPaths, x: int, y: int, button: str = "left", count: int = 1) -> dict[str, object]:
    return _pointer(paths, "click", [x, y, button, count])


def drag(paths: RealmPaths, x1: int, y1: int, x2: int, y2: int, button: str = "left") -> dict[str, object]:
    return _pointer(paths, "drag", [x1, y1, x2, y2, button])


def scroll(paths: RealmPaths, x: int, y: int, dx: int = 0, dy: int = 0) -> dict[str, object]:
    return _pointer(paths, "scroll", [x, y, dx, dy])


def type_text(paths: RealmPaths, text: str, delay_ms: int = 5) -> dict[str, object]:
    if not text:
        return {"typed": 0, "elapsed_ms": 0.0}
    wtype = shutil.which("wtype", path="/usr/bin:/bin")
    if not wtype:
        raise RealmError("wtype no está instalado; la escritura virtual requiere el protocolo virtual-keyboard")
    meta = _load(paths)
    env = _realm_env(paths, meta)
    before = time.monotonic()
    # Allow the compositor to install the new virtual keyboard's keymap before
    # its first key event; otherwise wtype's first character can be dropped.
    args = [wtype, "-s", str(WTYPE_START_DELAY_MS), "-P", "Shift_L", "-p", "Shift_L"]
    delay = max(0, min(1000, delay_ms))
    if delay:
        args += ["-d", str(delay)]
    args += ["--", text]
    result = subprocess.run(args, env=env, capture_output=True, text=True, timeout=60)
    if result.returncode != 0:
        raise RealmError(result.stderr.strip() or f"wtype terminó con {result.returncode}")
    return {"typed": len(text), "elapsed_ms": round((time.monotonic() - before) * 1000, 2)}


def key(paths: RealmPaths, chord: str) -> dict[str, object]:
    wtype = shutil.which("wtype", path="/usr/bin:/bin")
    if not wtype:
        raise RealmError("wtype no está instalado")
    aliases = {"CTRL": "ctrl", "CONTROL": "ctrl", "ALT": "alt", "SHIFT": "shift",
               "SUPER": "logo", "META": "logo", "WIN": "win", "ALTGR": "altgr"}
    parts = [part.strip() for part in chord.split("+") if part.strip()]
    if not parts:
        raise RealmError("key requiere un keysym o chord, por ejemplo CTRL+L o Escape")
    mods = []
    while len(parts) > 1:
        label = parts.pop(0).upper()
        if label not in aliases:
            raise RealmError(f"modificador desconocido: {label}")
        mods.append(aliases[label])
    key_name = parts[0]
    # A newly created virtual keyboard needs a short round of compositor time
    # after its keymap before the first key press is delivered.
    args: list[str] = ["-s", str(WTYPE_START_DELAY_MS), "-P", "Shift_L", "-p", "Shift_L"]
    for mod in mods:
        args += ["-M", mod]
    args += ["-k", key_name]
    for mod in reversed(mods):
        args += ["-m", mod]
    meta = _load(paths)
    before = time.monotonic()
    result = subprocess.run([wtype, *args], env=_realm_env(paths, meta),
                            capture_output=True, text=True, timeout=15)
    if result.returncode != 0:
        raise RealmError(result.stderr.strip() or f"wtype terminó con {result.returncode}")
    return {"key": chord, "elapsed_ms": round((time.monotonic() - before) * 1000, 2)}
