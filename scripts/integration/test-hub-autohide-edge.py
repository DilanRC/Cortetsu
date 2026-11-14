#!/usr/bin/env python3
"""The auto-hidden Hub comes back from the screen's very edge, in a nested Hyprland.

A pointer thrown at an edge stops on its last pixel. For each of the four
edges the hidden Hub must appear from there, stay while the pointer rests
on that pixel (no hide/reveal loop) and hide once the pointer leaves, and
its islands must keep the place they have without auto-hide.

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-hub-autohide-edge.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

# One anchor per edge.
EDGES = {"bottom-center": "bottom", "top-center": "top", "middle-left": "left", "middle-right": "right"}
# hyprctl monitors: reserved = [left, top, right, bottom]
RESERVED = {"left": 0, "top": 1, "right": 2, "bottom": 3}
FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type")


def shown(session: H.Session) -> bool:
    return session.ipc("bottomHub", "isShown").stdout.strip() == "true"


def edge_pixel(monitor: dict, edge: str) -> tuple[int, int]:
    x, y, w, h = monitor["x"], monitor["y"], monitor["width"], monitor["height"]
    return {"bottom": (x + w // 2, y + h - 1), "top": (x + w // 2, y),
            "left": (x, y + h // 2), "right": (x + w - 1, y + h // 2)}[edge]


def bell(session: H.Session) -> list[float]:
    return [float(v) for v in session.ipc("bottomHub", "notificationsButton").stdout.split()]


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="cz30-autohide-") as temporary:
        session = H.Session(Path(temporary))
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            session.focus_monitor(name)
            monitor = lambda: next(m for m in session.monitors() if m["name"] == name)  # noqa: E731
            centre = (monitor()["x"] + monitor()["width"] // 2, monitor()["y"] + monitor()["height"] // 2)
            session.move(*centre)

            # Where each anchor puts the bell without auto-hide.
            places = {}
            for anchor, edge in EDGES.items():
                assert session.ipc("bottomHub", "anchor", "", anchor).stdout.strip() == "true", anchor
                H.wait_for(lambda: inspect_anchor(session, name) == anchor, f"Hub en {anchor}")
                H.wait_for(lambda: monitor()["reserved"][RESERVED[edge]] >= 50, f"zona reservada en {anchor}")
                places[anchor] = H.settled(lambda: bell(session) or None, f"campana en {anchor}")
                places[anchor + ":reserved"] = H.settled(lambda: monitor()["reserved"], f"zona en {anchor}")

            # Auto-hide is a preference the shell reads at start.
            preferences = session.home / ".config/cortetsu/preferences.json"
            data = json.loads(preferences.read_text())
            data["bar"]["showOnHover"] = True
            preferences.write_text(json.dumps(data))
            session.restart_shell()

            for anchor, edge in EDGES.items():
                assert session.ipc("bottomHub", "anchor", "", anchor).stdout.strip() == "true", anchor
                H.wait_for(lambda: inspect_anchor(session, name) == anchor, f"Hub en {anchor}")
                session.move(*centre)
                H.wait_for(lambda: not shown(session), f"{anchor}: el Hub se oculta solo", 5)

                session.move(*edge_pixel(monitor(), edge))
                try:
                    H.wait_for(lambda: shown(session), f"{anchor}: el borde de la pantalla revela el Hub", 3)
                except AssertionError:
                    print("capas:", json.dumps(hub_layers(session, name)), "cursor:", session.hjson("cursorpos"))
                    raise
                # Resting on the edge pixel: shown the whole time.
                end = time.monotonic() + 1.5
                while time.monotonic() < end:
                    assert shown(session), f"{anchor}: el Hub se ocultó con el puntero quieto en el borde"
                    time.sleep(0.1)
                place = H.settled(lambda: bell(session) or None, f"campana revelada en {anchor}")
                assert place == places[anchor], f"{anchor}: las islas se movieron con auto-hide {place} != {places[anchor]}"
                reserved = H.settled(lambda: monitor()["reserved"], f"zona revelada en {anchor}")
                assert reserved == places[anchor + ":reserved"], \
                    f"{anchor}: zona reservada {reserved} != {places[anchor + ':reserved']}"

                session.move(*centre)
                H.wait_for(lambda: not shown(session), f"{anchor}: el Hub se oculta al salir", 5)

            # The anchor changes while the pointer rests on the strip: the
            # strip is replaced under it, and leaving must still hide the Hub.
            assert session.ipc("bottomHub", "anchor", "", "bottom-center").stdout.strip() == "true"
            H.wait_for(lambda: inspect_anchor(session, name) == "bottom-center", "Hub abajo")
            session.move(*centre)
            H.wait_for(lambda: not shown(session), "Hub oculto antes del cambio", 5)
            session.move(*edge_pixel(monitor(), "bottom"))
            H.wait_for(lambda: shown(session), "revelado desde abajo", 3)
            assert session.ipc("bottomHub", "anchor", "", "top-center").stdout.strip() == "true"
            H.wait_for(lambda: inspect_anchor(session, name) == "top-center", "Hub arriba con el puntero en el borde")
            time.sleep(0.5)
            session.move(*centre)
            H.wait_for(lambda: not shown(session), "el Hub se oculta tras cambiar de borde bajo el puntero", 5)

            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
        finally:
            session.stop()
    print("PASS: con auto-hide el Hub vuelve desde el último píxel de cada borde, se queda con el puntero "
          "en el borde, se oculta al salir (también tras cambiar de borde bajo el puntero) y conserva su sitio y su zona reservada")
    return 0


def hub_layers(session: H.Session, name: str) -> list[dict]:
    levels = ((session.hjson("layers") or {}).get(name) or {}).get("levels", {}).values()
    return [{k: layer[k] for k in ("namespace", "x", "y", "w", "h")}
            for level in levels for layer in level if "hub" in layer["namespace"]]


def inspect_anchor(session: H.Session, name: str) -> str:
    states = json.loads(session.ipc("bottomHub", "inspect").stdout or "[]")
    return next((s["hubAnchor"] for s in states if s["screen"] == name), "")


if __name__ == "__main__":
    sys.exit(main())
