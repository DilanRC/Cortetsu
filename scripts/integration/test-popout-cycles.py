#!/usr/bin/env python3
"""Phase 4 gate: Hub popouts and the tray menu, opened and closed many times.

In a nested Hyprland with two outputs and a real SNI/DBusMenu provider:

- 40 service popouts (audio, network, Bluetooth, battery), each opened on the
  focused monitor only and closed by the same control or by closeControl;
- 10 tray menus opened by a real right click on the tray icon and driven from
  the keyboard: the first usable row has focus, Right enters the submenu,
  Left leaves it, Enter runs the action at the provider, Escape or a click
  outside closes; a menu opened by hover holds no keys and closes when the
  pointer leaves;
- afterwards no popout is open anywhere, the layer surfaces are the ones the
  shell started with, memory has not climbed and the log is clean.

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-popout-cycles.py
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

FIXTURE = Path(__file__).resolve().parent / "status-notifier-fixture.py"
MODES = ("audio", "network", "bluetooth", "battery")
SERVICE_CYCLES = 40
TRAY_CYCLES = 10
BTN_RIGHT = 273
KEY_ESC, KEY_ENTER, KEY_LEFT, KEY_RIGHT, KEY_DOWN = 1, 28, 105, 106, 108
# Software rendering in a nested compositor; the live shell measured 353 MiB.
RSS_GROWTH_LIMIT_KIB = 48 * 1024
FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type")


def inspect(session: H.Session) -> dict[str, dict]:
    return {entry["screen"]: entry for entry in json.loads(session.ipc("bottomHub", "inspect").stdout)}


def layers(session: H.Session) -> list[str]:
    names = []
    for monitor in (session.hjson("layers") or {}).values():
        for level in monitor.get("levels", {}).values():
            names += [layer.get("namespace", "") for layer in level]
    return sorted(names)


def rss_kib(pid: int) -> int:
    for line in Path(f"/proc/{pid}/status").read_text().splitlines():
        if line.startswith("VmRSS:"):
            return int(line.split()[1])
    raise AssertionError("VmRSS missing")


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="cz30-cycles-") as temporary:
        session = H.Session(Path(temporary))
        fixture = None
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            other = next(m["name"] for m in session.monitors() if m["name"] != name)
            session.focus_monitor(name)

            fixture = subprocess.Popen([sys.executable, str(FIXTURE), "--instances", "1"], env=session.env(),
                                       stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                                       start_new_session=True)
            tray = H.settled(lambda: [float(v) for v in session.ipc("bottomHub", "trayButton").stdout.split()] or None,
                             "icono del proveedor SNI en la bandeja")
            assert len(tray) == 4 and tray[2] > 0, tray
            tx, ty = int(tray[0] + tray[2] / 2), int(tray[1] + tray[3] / 2)

            # Warm every popout once so the baseline counts loaded components.
            for mode in MODES:
                session.ipc("bottomHub", "control", mode)
                H.wait_for(lambda: inspect(session)[name]["open"], f"primer {mode}")
                session.ipc("bottomHub", "closeControl")
                H.wait_for(lambda: not inspect(session)[name]["open"], f"primer cierre de {mode}")
            time.sleep(1.0)
            baseline_layers = layers(session)
            baseline_rss = rss_kib(session.shell.pid)

            for cycle in range(SERVICE_CYCLES):
                mode = MODES[cycle % len(MODES)]
                assert session.ipc("bottomHub", "control", mode).stdout.strip() == "true", mode
                H.wait_for(lambda: inspect(session)[name]["open"] and inspect(session)[name]["popup"] == mode,
                           f"ciclo {cycle}: {mode} abierto")
                state = inspect(session)
                assert not state[other]["open"], f"ciclo {cycle}: popout también en {other}"
                if cycle % 2:
                    session.ipc("bottomHub", "control", mode)  # the same control closes it
                else:
                    session.ipc("bottomHub", "closeControl")
                H.wait_for(lambda: not inspect(session)[name]["open"], f"ciclo {cycle}: {mode} cerrado")

            actions = 0
            for cycle in range(TRAY_CYCLES):
                session.move(tx, ty)
                time.sleep(0.05)
                session.send(f"button {BTN_RIGHT} 1")
                time.sleep(0.03)
                session.send(f"button {BTN_RIGHT} 0")
                H.wait_for(lambda: inspect(session)[name]["open"] and inspect(session)[name]["tray"]["menuHandle"]
                           and inspect(session)[name]["tray"]["menuContentHeight"] > 0,
                           f"bandeja {cycle}: menú abierto")
                assert not inspect(session)[other]["open"], f"bandeja {cycle}: menú también en {other}"
                assert inspect(session)[name]["keyboardHeld"], f"bandeja {cycle}: el clic derecho no le dio el teclado al menú"
                time.sleep(0.3)
                if cycle == 0:
                    # Keyboard: one Down from "Action" (focused on opening)
                    # skips the disabled row and lands on "Submenu", the only
                    # row Right can open; Left comes back. Reaching depth 2
                    # proves the opening focus and the skip.
                    session.tap(KEY_DOWN)
                    time.sleep(0.15)
                    # The keys live on the Hub's tray icon, never in the
                    # menu's window: the row they act on must still be the one
                    # that shows the keyboard mark.
                    tray_state = inspect(session)[name]["tray"]
                    assert tray_state["focusedRow"] >= 0 and tray_state["markedRow"] == tray_state["focusedRow"], \
                        f"la fila elegida con el teclado no se ve: {tray_state}"
                    session.tap(KEY_RIGHT)
                    H.wait_for(lambda: inspect(session)[name]["tray"]["stackDepth"] == 2,
                               "submenú abierto con la flecha derecha")
                    session.tap(KEY_LEFT)
                    H.wait_for(lambda: inspect(session)[name]["tray"]["stackDepth"] == 1,
                               "vuelta al menú con la flecha izquierda")
                    session.tap(KEY_ESC)
                elif cycle == 1:
                    session.tap(KEY_ENTER)  # the first usable row is "Action"
                    actions += 1
                elif cycle % 2:
                    session.tap(KEY_ESC)
                else:
                    monitor = next(m for m in session.monitors() if m["name"] == name)
                    session.click(monitor["x"] + monitor["width"] // 2, monitor["y"] + monitor["height"] // 3)
                H.wait_for(lambda: not inspect(session)[name]["open"], f"bandeja {cycle}: menú cerrado")
                session.move(tx, ty - 300)

            # A menu closed by a key stays as it was while it closes: it used
            # to be rebuilt on screen at that moment (the close flips
            # hasCurrent), which crashed Qt's software renderer now and then
            # (REGISTRO, fase 4). Opened again while it closes or fades out, it
            # starts over at its first level, in place.
            #   "watch":   Escape, then look at it during the closing phase
            #   "closing": the click goes in while Escape is still held (Escape
            #              acts on press), inside the 120 ms closing phase
            #   "fade":    0.2 s later, during the fade that follows
            for case in ("watch", "closing", "fade"):
                session.move(tx, ty)
                time.sleep(0.05)
                session.send(f"button {BTN_RIGHT} 1")
                time.sleep(0.03)
                session.send(f"button {BTN_RIGHT} 0")
                H.wait_for(lambda: inspect(session)[name]["tray"]["menuContentHeight"] > 0, f"{case}: menú")
                time.sleep(0.3)
                session.tap(KEY_DOWN)
                time.sleep(0.15)
                session.tap(KEY_RIGHT)
                H.wait_for(lambda: inspect(session)[name]["tray"]["stackDepth"] == 2, f"{case}: submenú")
                if case == "watch":
                    session.send(f"key {KEY_ESC} 1")
                    seen = [inspect(session)[name] for _ in range(4)]
                    session.send(f"key {KEY_ESC} 0")
                    closing = [state for state in seen if state["open"] and state["closing"]]
                    assert closing, f"no se vio la fase de cierre: {seen}"
                    assert all(state["tray"]["stackDepth"] == 2 for state in closing), \
                        f"el menú se reconstruyó en pantalla al cerrarse: {[s['tray'] for s in closing]}"
                    H.wait_for(lambda: not inspect(session)[name]["open"], "cerrado sin reconstruirse")
                    session.move(tx, ty - 300)
                    time.sleep(0.6)
                    continue
                if case == "closing":
                    session.send(f"key {KEY_ESC} 1")
                    session.send(f"button {BTN_RIGHT} 1")
                    session.send(f"button {BTN_RIGHT} 0")
                    session.send(f"key {KEY_ESC} 0")
                else:
                    session.tap(KEY_ESC)
                    time.sleep(0.2)
                    session.send(f"button {BTN_RIGHT} 1")
                    time.sleep(0.03)
                    session.send(f"button {BTN_RIGHT} 0")
                H.wait_for(lambda: inspect(session)[name]["open"] and not inspect(session)[name]["closing"],
                           f"{case}: reabierto")
                time.sleep(0.4)
                state = inspect(session)[name]
                assert state["open"] and state["tray"]["stackDepth"] == 1, f"{case}: reabierto en el primer nivel: {state}"
                session.tap(KEY_ESC)
                H.wait_for(lambda: not inspect(session)[name]["open"], f"{case}: cerrado")
                session.move(tx, ty - 300)
                time.sleep(0.6)

            # Resting on the icon opens the menu without taking the keyboard,
            # and leaving for anywhere but the menu closes it (it used to stay).
            session.move(tx, ty)
            H.wait_for(lambda: inspect(session)[name]["open"], "menú abierto por hover")
            assert not inspect(session)[name]["keyboardHeld"], "un menú abierto por hover no toma el teclado"
            session.move(tx, ty - 300)
            H.wait_for(lambda: not inspect(session)[name]["open"], "menú de hover cerrado al salir")

            session.ipc("bottomHub", "closeControl")
            time.sleep(1.5)
            final = inspect(session)
            assert not any(entry["open"] for entry in final.values()), final
            assert layers(session) == baseline_layers, (baseline_layers, layers(session))
            growth = rss_kib(session.shell.pid) - baseline_rss
            assert growth < RSS_GROWTH_LIMIT_KIB, f"RSS creció {growth // 1024} MiB en {SERVICE_CYCLES + TRAY_CYCLES} ciclos"

            fixture.terminate()
            output = fixture.communicate(timeout=10)[0]
            fixture = None
            assert output.count("action 1 count=") == actions, f"Enter no llegó al proveedor:\n{output}"

            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
            # The crash handler restarts the shell in place: without this a
            # crash between two checks would go unseen.
            assert not session.crash_reports(), "Quickshell se cayó y se reinició durante la prueba"
        except Exception:
            log = session.logs / "qs.log"
            if log.exists():
                print("--- qs.log (final) ---\n" + "\n".join(log.read_text(errors="replace").splitlines()[-60:]))
            raise
        finally:
            if fixture and fixture.poll() is None:
                fixture.terminate()
                fixture.wait(10)
            session.stop()
    print(f"PASS: {SERVICE_CYCLES} popouts de servicio y {TRAY_CYCLES} menús de bandeja abren en un solo monitor, "
          f"responden al teclado y cierran sin dejar superficies (RSS +{growth // 1024} MiB)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
