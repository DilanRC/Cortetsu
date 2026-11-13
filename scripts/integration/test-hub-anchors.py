#!/usr/bin/env python3
"""The Hub on each of its eight anchors, in a nested Hyprland.

For every anchor: the layer surface sits on that edge, the compositor
reserves the Hub's thickness there and nowhere else, and an attached popout
opens inwards, wholly inside the screen. Then a monitor gets an anchor of its
own while the other keeps the default, and an unknown anchor is refused.

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-hub-anchors.py [--shots DIR]
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

ANCHORS = {
    "top-left": "top", "top-center": "top", "top-right": "top",
    "middle-left": "left", "middle-right": "right",
    "bottom-left": "bottom", "bottom-center": "bottom", "bottom-right": "bottom",
}
# hyprctl monitors: reserved = [left, top, right, bottom]
RESERVED = {"left": 0, "top": 1, "right": 2, "bottom": 3}
FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type")


def hub_layer(session: H.Session, monitor: str) -> dict | None:
    layers = session.hjson("layers") or {}
    for level in (layers.get(monitor) or {}).get("levels", {}).values():
        for layer in level:
            if layer.get("namespace") == "cortetsu-bottom-hub":
                return layer
    return None


def on_edge(layer: dict | None, monitor: dict, edge: str) -> bool:
    if not layer:
        return False
    x, y = layer["x"] - monitor["x"], layer["y"] - monitor["y"]
    w, h = layer["w"], layer["h"]
    if edge == "bottom":
        return w > monitor["width"] * 0.9 and abs(y + h - (monitor["height"] - 2)) <= 1
    if edge == "top":
        return w > monitor["width"] * 0.9 and abs(y - 2) <= 1
    if edge == "left":
        return h > monitor["height"] * 0.9 and abs(x - 2) <= 1
    return h > monitor["height"] * 0.9 and abs(x + w - (monitor["width"] - 2)) <= 1


def inspect(session: H.Session, monitor: str) -> dict:
    data = json.loads(session.ipc("bottomHub", "inspect").stdout)
    return next(entry for entry in data if entry["screen"] == monitor)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--shots", type=Path, help="save one screenshot per anchor here")
    args = parser.parse_args()
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    if args.shots:
        args.shots.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="cz30-hub-") as temporary:
        session = H.Session(Path(temporary))
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            other = next(m["name"] for m in session.monitors() if m["name"] != name)
            session.focus_monitor(name)

            def monitor() -> dict:
                return next(m for m in session.monitors() if m["name"] == name)

            for anchor, edge in ANCHORS.items():
                assert session.ipc("bottomHub", "anchor", "", anchor).stdout.strip() == "true", anchor
                H.wait_for(lambda: on_edge(hub_layer(session, name), monitor(), edge), f"Hub en {anchor}")
                H.wait_for(lambda: monitor()["reserved"][RESERVED[edge]] >= 50, f"zona reservada en {anchor}")
                reserved = monitor()["reserved"]
                assert [i for i, value in enumerate(reserved) if value >= 50] == [RESERVED[edge]], (anchor, reserved)
                assert json.loads(session.ipc("bottomHub", "anchors").stdout)[name] == anchor

                assert session.ipc("bottomHub", "control", "audio").stdout.strip() == "true", anchor
                H.wait_for(lambda: inspect(session, name)["open"] and inspect(session, name)["popupRect"][2] > 100,
                           f"popout abierto en {anchor}")
                time.sleep(0.4)
                state = inspect(session, name)
                assert state["hubAnchor"] == anchor, state
                x, y, w, h = state["popupRect"]
                width, height = monitor()["width"], monitor()["height"]
                assert x >= 0 and y >= 0 and x + w <= width and y + h <= height, (anchor, state["popupRect"])
                clear = {"bottom": y + h <= height - 56, "top": y >= 56,
                         "left": x >= 56, "right": x + w <= width - 56}[edge]
                assert clear, f"{anchor}: el popout {state['popupRect']} pisa el Hub"
                if args.shots and shutil.which("grim"):
                    subprocess.run(["grim", "-o", name, str(args.shots / f"hub-{anchor}.png")],
                                   env=session.env(), check=False, timeout=20)
                session.ipc("bottomHub", "closeControl")
                H.wait_for(lambda: not inspect(session, name)["open"], f"popout cerrado en {anchor}")

                # The input mask follows the islands: a real click on the bell,
                # where the Hub says it is, opens the notification panel.
                session.focus_monitor(name)
                bell = [float(value) for value in session.ipc("bottomHub", "notificationsButton").stdout.split()]
                assert len(bell) == 4 and bell[2] > 0, (anchor, bell)
                # Hover: the battery control sits just before the bell along
                # the Hub. Resting on it opens its popout, and the popout
                # stays while the pointer crosses the gap and rests inside.
                lateral = edge in ("left", "right")
                bx, by = int(bell[0] + bell[2] / 2), int(bell[1] + bell[3] / 2)
                session.move(bx if lateral else int(bell[0]) - 22, int(bell[1]) - 22 if lateral else by)
                H.wait_for(lambda: inspect(session, name)["popup"] == "battery" and inspect(session, name)["open"],
                           f"popout por hover en {anchor}")
                time.sleep(0.4)
                px, py, pw, ph = inspect(session, name)["popupRect"]
                session.move(monitor()["x"] + int(px + pw / 2), monitor()["y"] + int(py + ph / 2))
                time.sleep(1.2)
                held = inspect(session, name)
                assert held["open"] and not held["closing"] and held["popup"] == "battery", (anchor, held)
                session.move(monitor()["x"] + monitor()["width"] // 2, monitor()["y"] + monitor()["height"] // 2)
                H.wait_for(lambda: not inspect(session, name)["open"], f"popout cerrado al salir en {anchor}")

                session.click(bx, by)
                H.wait_for(lambda: inspect(session, name)["sidebar"], f"clic en la campana en {anchor}")
                session.ipc("bottomHub", "notifications")
                H.wait_for(lambda: not inspect(session, name)["sidebar"], f"panel de avisos cerrado en {anchor}")

            # One monitor moves; the other keeps the default.
            assert session.ipc("bottomHub", "anchor", "", "bottom-center").stdout.strip() == "true"
            assert session.ipc("bottomHub", "anchor", name, "top-right").stdout.strip() == "true"
            H.wait_for(lambda: on_edge(hub_layer(session, name), monitor(), "top"), "anclaje propio del monitor")
            placed = json.loads(session.ipc("bottomHub", "anchors").stdout)
            assert placed[name] == "top-right" and placed[other] == "bottom-center", placed
            # An unknown anchor is refused and nothing moves.
            assert session.ipc("bottomHub", "anchor", name, "centre").stdout.strip() == "false"
            assert json.loads(session.ipc("bottomHub", "anchors").stdout) == placed
            # The preference survives as written and comes back by clearing it.
            preferences = session.home / ".config/cortetsu/preferences.json"

            def saved_anchors() -> dict | None:
                try:
                    return json.loads(preferences.read_text())["bottomHub"].get("anchors")
                except (OSError, ValueError, KeyError):
                    return None
            H.wait_for(lambda: saved_anchors() == {name: "top-right"}, "anclaje guardado en preferencias")
            session.ipc("bottomHub", "clearAnchor", name)
            H.wait_for(lambda: on_edge(hub_layer(session, name), monitor(), "bottom"), "vuelta al anclaje común")

            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
        finally:
            session.stop()
    print("PASS: el Hub ocupa sus ocho anclajes, reserva solo su borde, abre los popouts hacia dentro "
          "y admite un anclaje por monitor")
    return 0


if __name__ == "__main__":
    sys.exit(main())
