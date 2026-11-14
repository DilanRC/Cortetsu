#!/usr/bin/env python3
"""Phase 4 gate: the App Rail's window preview and the Hub's edit mode.

In a nested Hyprland with real windows, a real pointer and keyboard:

Preview
- resting on a running app opens its windows after a dwell (not before), one
  card per window, without taking the keyboard; leaving closes it;
- the Menu key on the icon opens it with the keyboard: it starts on the
  active window, Right moves, Enter goes to that window and closes;
- a window that goes away under the open preview takes only its card;
- Escape and a click outside close it; the Aplicaciones island is engaged
  only while it shows;
- on a lateral Hub the preview opens beside it, inside the screen.

Edit mode
- it covers only the monitor being edited and holds the keyboard;
- dragging the Hub lights the place it would snap to; dropped, it settles;
- Escape leaves everything as it was; Enter saves for that monitor only and
  the Hub really moves there (a lateral one stands upright);
- Home goes back to the default place;
- a monitor unplugged while editing ends the edit, leaving no surface;
- a monitor's own place comes back when it is plugged in again, also at a
  scale of 1.25.

Afterwards: the shell's layers are the ones it started with, it never
crashed and its log is clean.

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-hub-previews-edit.py
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import launcher_harness as H  # noqa: E402

BTN_LEFT = 272
KEY_ESC, KEY_ENTER, KEY_RIGHT, KEY_LEFT, KEY_HOME, KEY_MENU = 1, 28, 106, 105, 102, 127
FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type",
            "more visible items")
DWELL_S = 0.45


def inspect(session: H.Session, monitor: str) -> dict:
    return {e["screen"]: e for e in json.loads(session.ipc("bottomHub", "inspect").stdout)}[monitor]


def layer(session: H.Session, monitor: str, namespace: str) -> dict | None:
    for level in ((session.hjson("layers") or {}).get(monitor) or {}).get("levels", {}).values():
        for entry in level:
            if entry.get("namespace") == namespace:
                return entry
    return None


def all_layers(session: H.Session) -> list[str]:
    names = []
    for monitor in (session.hjson("layers") or {}).values():
        for level in monitor.get("levels", {}).values():
            names += [entry.get("namespace", "") for entry in level]
    return sorted(names)


def edit_state(session: H.Session) -> list[str]:
    return session.ipc("bottomHub", "editState").stdout.split()


def kitty(session: H.Session, title: str) -> subprocess.Popen:
    return subprocess.Popen(["kitty", "--config", "NONE", "--class", "cortetsu-probe", "--title", title,
                             "sh", "-c", "sleep 900"], env=session.env(), stdout=subprocess.DEVNULL,
                            stderr=subprocess.DEVNULL, start_new_session=True)


def inside(rect: list[float], monitor: dict) -> bool:
    """`rect` in the monitor's own coordinates (inspect's popupRect)."""
    x, y, w, h = rect
    return x >= 0 and y >= 0 and x + w <= monitor["width"] and y + h <= monitor["height"]


def drag(session: H.Session, start: tuple[float, float], end: tuple[float, float]) -> None:
    session.move(int(start[0]), int(start[1]))
    time.sleep(0.15)
    session.send(f"button {BTN_LEFT} 1")
    time.sleep(0.1)
    for i in range(1, 21):
        session.move(int(start[0] + (end[0] - start[0]) * i / 20), int(start[1] + (end[1] - start[1]) * i / 20))
        time.sleep(0.03)
    time.sleep(0.2)


def check_preview(session: H.Session, name: str, kids: list) -> None:
    apps = json.loads(session.ipc("bottomHub", "apps").stdout)
    key = next(a["key"] for a in apps if a["running"] and a["windows"] == 3)
    rect = H.settled(lambda: [float(v) for v in session.ipc("bottomHub", "appButton", key).stdout.split()] or None,
                     "icono de la aplicación")
    cx, cy = int(rect[0] + rect[2] / 2), int(rect[1] + rect[3] / 2)
    monitor = next(m for m in session.monitors() if m["name"] == name)

    # Hover: nothing during the dwell, then the cards; no keyboard.
    session.move(cx, cy - 250)
    time.sleep(0.3)
    session.move(cx, cy)
    time.sleep(DWELL_S * 0.5)
    assert not inspect(session, name)["open"], "la vista previa se abrió antes de la espera"
    H.wait_for(lambda: inspect(session, name)["preview"]["cards"] == 3, "vista previa por hover", 10)
    state = inspect(session, name)
    assert not state["keyboardHeld"], "una vista previa por hover no toma el teclado"
    assert state["engaged"][1] and not any(state["engaged"][i] for i in (0, 2, 3)), state["engaged"]
    assert inside(state["popupRect"], monitor), state["popupRect"]
    session.move(cx, cy - 400)
    H.wait_for(lambda: not inspect(session, name)["open"], "vista previa cerrada al salir", 10)
    H.wait_for(lambda: not any(inspect(session, name)["engaged"]), "isla en reposo", 5)

    # Keyboard: Menu on the icon, Right, Enter goes to that window.
    session.click(cx, cy)
    time.sleep(0.5)
    session.tap(KEY_MENU)
    H.wait_for(lambda: inspect(session, name)["open"] and inspect(session, name)["keyboardHeld"], "Menú", 10)
    H.wait_for(lambda: inspect(session, name)["preview"]["selected"] >= 0, "selección inicial", 5)
    active = (session.hjson("activewindow") or {}).get("title")
    first = inspect(session, name)["preview"]["selected"]
    session.tap(KEY_RIGHT if first < 2 else KEY_LEFT)
    H.wait_for(lambda: inspect(session, name)["preview"]["selected"] != first, "flecha", 5)
    session.tap(KEY_ENTER)
    H.wait_for(lambda: not inspect(session, name)["open"], "Intro cierra", 10)
    H.wait_for(lambda: (session.hjson("activewindow") or {}).get("title") not in (None, active),
               "Intro lleva a otra ventana", 10)

    # A window gone under the open preview takes only its card.
    session.click(cx, cy)
    time.sleep(0.5)
    session.tap(KEY_MENU)
    H.wait_for(lambda: inspect(session, name)["preview"]["cards"] == 3, "vista previa abierta", 10)
    kids[1].terminate()  # kitty asks before closing a window with a program in it
    H.wait_for(lambda: inspect(session, name)["preview"]["cards"] == 2, "tarjeta retirada", 10)
    assert inspect(session, name)["open"], "la vista previa sigue abierta con las ventanas restantes"
    session.tap(KEY_ESC)
    H.wait_for(lambda: not inspect(session, name)["open"], "Esc cierra", 10)

    # A click outside closes one opened from the keyboard (focus grab).
    session.click(cx, cy)
    time.sleep(0.5)
    session.tap(KEY_MENU)
    H.wait_for(lambda: inspect(session, name)["open"], "vista previa para el clic fuera", 10)
    session.click(monitor["x"] + monitor["width"] // 2, monitor["y"] + monitor["height"] // 4)
    H.wait_for(lambda: not inspect(session, name)["open"], "clic fuera cierra", 10)

    # Lateral Hub: beside it, inside the screen.
    session.ipc("bottomHub", "anchor", name, "middle-right")
    H.wait_for(lambda: inspect(session, name)["hubAnchor"] == "middle-right", "Hub lateral", 10)
    rect = H.settled(lambda: [float(v) for v in session.ipc("bottomHub", "appButton", key).stdout.split()] or None,
                     "icono en el Hub lateral")
    session.click(int(rect[0] + rect[2] / 2), int(rect[1] + rect[3] / 2))
    time.sleep(0.5)
    session.tap(KEY_MENU)
    H.wait_for(lambda: inspect(session, name)["open"], "vista previa con el Hub lateral", 10)
    time.sleep(0.6)
    popup = inspect(session, name)["popupRect"]
    assert inside(popup, monitor), popup
    assert monitor["x"] + popup[0] + popup[2] <= rect[0], f"la vista previa se abre a la izquierda del Hub: {popup} {rect}"
    session.tap(KEY_ESC)
    H.wait_for(lambda: not inspect(session, name)["open"], "Esc con el Hub lateral", 10)
    session.ipc("bottomHub", "clearAnchor", name)
    H.wait_for(lambda: inspect(session, name)["hubAnchor"] == "bottom-center", "Hub de vuelta abajo", 10)


def check_edit_mode(session: H.Session, name: str, other: str) -> None:
    monitor = lambda: next(m for m in session.monitors() if m["name"] == name)  # noqa: E731
    session.focus_monitor(name)
    assert session.ipc("bottomHub", "editMode", "").stdout.strip() == "true"
    H.wait_for(lambda: layer(session, name, "cortetsu-hub-edit"), "superficie de edición", 10)
    assert not layer(session, other, "cortetsu-hub-edit"), "el modo edición cubre solo su monitor"
    assert session.keyboard_layer() in ("", "cortetsu-hub-edit")
    time.sleep(0.6)

    # Drag to the top right: it lights up while dragging and settles there.
    st = edit_state(session)
    m = monitor()
    ghost = (float(st[2]) + float(st[4]) / 2, float(st[3]) + float(st[5]) / 2)
    drag(session, ghost, (m["x"] + m["width"] - 60, m["y"] + 40))
    assert edit_state(session)[1] == "top-right", edit_state(session)
    session.send(f"button {BTN_LEFT} 0")
    time.sleep(0.8)
    st = edit_state(session)
    assert st[1] == "top-right" and float(st[3]) - m["y"] <= 4, f"se asienta arriba a la derecha: {st}"
    # Escape: nothing changed.
    session.tap(KEY_ESC)
    H.wait_for(lambda: not layer(session, name, "cortetsu-hub-edit"), "Esc cierra el modo edición", 10)
    anchors = json.loads(session.ipc("bottomHub", "anchors").stdout)
    assert anchors[name] == "bottom-center", f"Esc no guarda: {anchors}"

    # Drag to the left side and save with Enter: only this monitor moves,
    # and the Hub stands upright.
    session.ipc("bottomHub", "editMode", name)
    H.wait_for(lambda: edit_state(session), "modo edición otra vez", 10)
    time.sleep(0.6)
    st = edit_state(session)
    ghost = (float(st[2]) + float(st[4]) / 2, float(st[3]) + float(st[5]) / 2)
    drag(session, ghost, (m["x"] + 30, m["y"] + m["height"] // 2))
    session.send(f"button {BTN_LEFT} 0")
    time.sleep(0.6)
    assert edit_state(session)[1] == "middle-left", edit_state(session)
    session.tap(KEY_ENTER)
    H.wait_for(lambda: inspect(session, name)["hubAnchor"] == "middle-left", "Intro guarda", 10)
    anchors = json.loads(session.ipc("bottomHub", "anchors").stdout)
    assert anchors[other] == "bottom-center", f"el otro monitor no se mueve: {anchors}"
    hub = H.wait_for(lambda: (lambda l: l if l and l["h"] > l["w"] and l["x"] - m["x"] <= 4 else None)(
        layer(session, name, "cortetsu-bottom-hub")), "Hub vertical a la izquierda", 10)
    assert hub["h"] > m["height"] * 0.9, hub

    # Home: the default place.
    session.ipc("bottomHub", "editMode", name)
    H.wait_for(lambda: edit_state(session), "modo edición para restablecer", 10)
    time.sleep(0.4)
    session.tap(KEY_HOME)
    H.wait_for(lambda: edit_state(session)[1] == "bottom-center", "Inicio elige la posición predeterminada", 5)
    session.tap(KEY_ENTER)
    H.wait_for(lambda: inspect(session, name)["hubAnchor"] == "bottom-center", "restablecido", 10)


def check_monitor_changes(session: H.Session) -> None:
    # Unplugged while editing: the edit ends and leaves nothing behind.
    session.hyprctl("output", "create", "headless", "CZ-EDIT")
    H.wait_for(lambda: any(m["name"] == "CZ-EDIT" for m in session.monitors()), "salida CZ-EDIT", 10)
    H.wait_for(lambda: layer(session, "CZ-EDIT", "cortetsu-bottom-hub"), "Hub en CZ-EDIT", 15)
    assert session.ipc("bottomHub", "editMode", "CZ-EDIT").stdout.strip() == "true"
    H.wait_for(lambda: layer(session, "CZ-EDIT", "cortetsu-hub-edit"), "edición en CZ-EDIT", 10)
    session.hyprctl("output", "remove", "CZ-EDIT")
    H.wait_for(lambda: not edit_state(session), "la edición termina con su monitor", 10)
    assert "cortetsu-hub-edit" not in all_layers(session), all_layers(session)

    # A monitor's own place comes back with it, at a scale of 1.25.
    session.hyprctl("output", "create", "headless", "CZ-SCALE")
    H.wait_for(lambda: any(m["name"] == "CZ-SCALE" for m in session.monitors()), "salida CZ-SCALE", 10)
    session.hyprctl("eval", 'hl.monitor({ output = "CZ-SCALE", mode = "1920x1080@60", position = "auto", scale = 1.25 })')
    H.wait_for(lambda: next((m["scale"] for m in session.monitors() if m["name"] == "CZ-SCALE"), 0) == 1.25,
               "escala 1.25", 10)
    session.ipc("bottomHub", "anchor", "CZ-SCALE", "top-right")
    H.wait_for(lambda: (lambda l: l and l["y"] - next(m for m in session.monitors() if m["name"] == "CZ-SCALE")["y"] <= 4)(
        layer(session, "CZ-SCALE", "cortetsu-bottom-hub")), "Hub arriba en CZ-SCALE", 15)
    session.hyprctl("output", "remove", "CZ-SCALE")
    H.wait_for(lambda: not any(m["name"] == "CZ-SCALE" for m in session.monitors()), "CZ-SCALE retirada", 10)
    assert json.loads(session.ipc("bottomHub", "anchors").stdout).get("CZ-SCALE") is None
    session.hyprctl("output", "create", "headless", "CZ-SCALE")
    H.wait_for(lambda: any(m["name"] == "CZ-SCALE" for m in session.monitors()), "CZ-SCALE de vuelta", 10)
    session.hyprctl("eval", 'hl.monitor({ output = "CZ-SCALE", mode = "1920x1080@60", position = "auto", scale = 1.25 })')

    def back_on_top():
        mon = next((m for m in session.monitors() if m["name"] == "CZ-SCALE"), None)
        hub = layer(session, "CZ-SCALE", "cortetsu-bottom-hub")
        return mon and mon["scale"] == 1.25 and hub and hub["y"] - mon["y"] <= 4 and hub["w"] < mon["width"]
    H.wait_for(back_on_top, "la posición propia vuelve con su monitor, a escala 1.25", 15)
    session.hyprctl("output", "remove", "CZ-SCALE")
    H.wait_for(lambda: not any(m["name"] == "CZ-SCALE" for m in session.monitors()), "CZ-SCALE retirada", 10)


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="cz30-preview-edit-") as temporary:
        session = H.Session(Path(temporary))
        kids: list[subprocess.Popen] = []
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            other = next(m["name"] for m in session.monitors() if m["name"] != name)
            session.focus_monitor(name)
            time.sleep(1.0)
            baseline = all_layers(session)
            for workspace, title in ((1, "Uno"), (2, "Dos"), (1, "Tres")):
                session.hyprctl("dispatch", f"hl.dsp.focus({{ workspace = {workspace} }})")
                time.sleep(0.3)
                kids.append(kitty(session, title))
                H.wait_for(lambda t=title: any(c.get("title") == t for c in session.hjson("clients") or []),
                           f"ventana {title}", 20)
            session.hyprctl("dispatch", "hl.dsp.focus({ workspace = 1 })")
            time.sleep(1.0)

            check_preview(session, name, kids)
            check_edit_mode(session, name, other)
            for kid in kids:
                kid.terminate()
            H.wait_for(lambda: not any(c.get("class") == "cortetsu-probe" for c in session.hjson("clients") or []),
                       "ventanas de prueba cerradas", 15)
            check_monitor_changes(session)

            time.sleep(1.0)
            assert all_layers(session) == baseline, (baseline, all_layers(session))
            assert not session.crash_reports(), "Quickshell se cayó y se reinició durante la prueba"
            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
        except Exception:
            log = session.logs / "qs.log"
            if log.exists():
                print("--- qs.log (final) ---\n" + "\n".join(
                    line for line in log.read_text(errors="replace").splitlines()[-80:] if "grain.png" not in line))
            raise
        finally:
            for kid in kids:
                if kid.poll() is None:
                    kid.terminate()
            session.stop()
    print("PASS: vista previa de ventanas (hover, teclado, ventana cerrada, clic fuera, Hub lateral) y modo edición "
          "(arrastre, Esc, Intro por monitor, Inicio, monitor retirado, posición propia a escala 1.25)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
