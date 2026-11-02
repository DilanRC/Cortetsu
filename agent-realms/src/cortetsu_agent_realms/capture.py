"""In-memory captures of one realm output, with the geometry needed to map pixels back.

Every capture runs grim against the realm's own Wayland socket and writes to a
pipe; nothing touches the filesystem, so observers and MCP never serve paths.
"""
from __future__ import annotations

import json
import itertools
import os
import re
import shutil
import struct
import subprocess
import time
from dataclasses import dataclass, field
from typing import Any

from .paths import RealmError, paths_for
from .process import load_meta, process_alive

MAX_FRAME_BYTES = 64 * 1024 * 1024
_MONITOR_RE = re.compile(r"^[A-Za-z0-9_-]{1,64}$")
_counter = itertools.count(1)


@dataclass(frozen=True)
class Monitor:
    name: str
    x: int
    y: int
    width: int   # pixels
    height: int  # pixels
    scale: float
    focused: bool = False

    @property
    def logical_width(self) -> float:
        return self.width / self.scale

    @property
    def logical_height(self) -> float:
        return self.height / self.scale


@dataclass(frozen=True)
class Frame:
    data: bytes
    realm: str
    monitor: Monitor
    # Captured area in Hyprland layout (logical) coordinates.
    region: tuple[float, float, float, float]
    delivered: tuple[int, int]
    image_format: str
    frame_id: str
    session: str
    captured_at: float = field(default_factory=time.time)

    @property
    def original(self) -> tuple[int, int]:
        _x, _y, w, h = self.region
        return round(w * self.monitor.scale), round(h * self.monitor.scale)

    @property
    def scale(self) -> float:
        """Delivered image pixels per logical desktop unit."""
        return self.delivered[0] / self.region[2]

    def to_desktop(self, ix: float, iy: float) -> tuple[int, int]:
        """Map an image coordinate to the realm's layout coordinate, refusing points outside the image."""
        width, height = self.delivered
        if not (0 <= ix < width and 0 <= iy < height):
            raise RealmError(f"({ix}, {iy}) está fuera de la imagen {width}x{height} del frame {self.frame_id}")
        rx, ry, rw, rh = self.region
        return int(rx + ix * rw / width), int(ry + iy * rh / height)

    def metadata(self) -> dict[str, Any]:
        return {"frame_id": self.frame_id, "realm": self.realm, "monitor": self.monitor.name,
                "original_resolution": list(self.original), "delivered_resolution": list(self.delivered),
                "scale": round(self.scale, 6), "monitor_scale": self.monitor.scale,
                "region": [round(v, 3) for v in self.region], "format": self.image_format,
                "captured_at": round(self.captured_at, 3)}


def session_identity(meta: dict[str, Any]) -> str:
    """Identity of one realm run; a restart under the same name yields a new value."""
    return f"{meta.get('systemd_scope_unit')}:{meta.get('leader_start_time')}"


def monitors(name: str) -> list[Monitor]:
    from .runtime import private_call
    result = private_call(name, ["-j", "monitors"])
    if result.returncode != 0:
        raise RealmError("no se pudieron consultar los monitores del realm: " + result.stderr.strip())
    try:
        raw = json.loads(result.stdout)
        found = []
        for item in raw:
            mon = Monitor(name=str(item["name"]), x=int(item["x"]), y=int(item["y"]),
                          width=int(item["width"]), height=int(item["height"]),
                          scale=float(item.get("scale", 1) or 1), focused=bool(item.get("focused")))
            if not _MONITOR_RE.fullmatch(mon.name) or mon.width <= 0 or mon.height <= 0 or mon.scale <= 0:
                raise ValueError(f"monitor inválido {mon.name!r}")
            found.append(mon)
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        raise RealmError(f"respuesta de monitores inválida: {exc}") from exc
    if not found:
        raise RealmError("el realm no tiene monitores")
    return found


def pick_monitor(available: list[Monitor], wanted: str | None) -> Monitor:
    if wanted is None:
        return next((m for m in available if m.focused), available[0])
    for mon in available:
        if mon.name == wanted:
            return mon
    raise RealmError(f"el realm no tiene el monitor {wanted!r}; disponibles: " +
                     ", ".join(m.name for m in available))


def image_size(data: bytes, image_format: str) -> tuple[int, int]:
    if image_format == "png":
        if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
            raise RealmError("grim no devolvió un PNG válido")
        return struct.unpack(">II", data[16:24])
    if image_format == "ppm":
        parts = data[:64].split(maxsplit=3)
        if len(parts) < 3 or parts[0] != b"P6":
            raise RealmError("grim no devolvió un PPM válido")
        return int(parts[1]), int(parts[2])
    raise RealmError(f"formato no admitido: {image_format}")


def capture(name: str, *, monitor: str | None = None, scale: float | None = None,
            region: tuple[int, int, int, int] | None = None, image_format: str = "png",
            png_level: int = 6) -> Frame:
    """Capture one output of `name`. `scale` is delivered pixels per logical unit."""
    paths = paths_for(name)
    meta = load_meta(paths)
    if not process_alive(meta) or meta.get("state") not in {"running", "degraded"}:
        raise RealmError(f"la sesión {name!r} no está activa")
    if image_format not in {"png", "ppm"}:
        raise RealmError("formato de captura no admitido")
    if scale is not None and not (0.05 <= scale <= 4):
        raise RealmError("scale debe estar entre 0.05 y 4")
    mon = pick_monitor(monitors(name), monitor)
    if region is None:
        area = (float(mon.x), float(mon.y), mon.logical_width, mon.logical_height)
    else:
        rx, ry, rw, rh = region
        if rw <= 0 or rh <= 0 or rx < mon.x or ry < mon.y or \
                rx + rw > mon.x + mon.logical_width or ry + rh > mon.y + mon.logical_height:
            raise RealmError(f"la región {region} no cabe en el monitor {mon.name}")
        area = (float(rx), float(ry), float(rw), float(rh))
    from .runtime import _realm_env
    grim = shutil.which("grim", path="/usr/bin:/bin")
    if not grim:
        raise RealmError("grim no está instalado")
    args = [grim, "-t", image_format]
    if image_format == "png":
        args += ["-l", str(max(0, min(9, png_level)))]
    args += ["-s", f"{scale if scale is not None else mon.scale:g}"]
    if region is None:
        args += ["-o", mon.name]
    else:
        args += ["-g", f"{int(area[0])},{int(area[1])} {int(area[2])}x{int(area[3])}"]
    args.append("-")
    result = subprocess.run(args, env=_realm_env(paths, meta), capture_output=True, timeout=20)
    if result.returncode != 0:
        raise RealmError(result.stderr.decode(errors="replace").strip() or "grim falló al capturar el realm")
    data = result.stdout
    if not data or len(data) > MAX_FRAME_BYTES:
        raise RealmError("grim devolvió una captura vacía o demasiado grande")
    delivered = image_size(data, image_format)
    frame_id = f"{os.getpid():x}-{next(_counter)}-{os.urandom(3).hex()}"
    return Frame(data=data, realm=name, monitor=mon, region=area, delivered=delivered,
                 image_format=image_format, frame_id=frame_id, session=session_identity(meta))
