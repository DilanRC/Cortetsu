#!/usr/bin/env python3
"""A tray app that comes and goes before any popout opened, in a nested Hyprland.

The Hub's tray icons and the popout that holds their menus key each app with
`tray-instance-N`. The popout content is built only when the first popout
opens. When the two kept separate counters (the same JS library imported by
two URLs), an app that appeared and left before that moment shifted one
counter: the next app's right click asked for a menu name nobody had, and an
empty popout stayed open holding the keyboard (seen on the live session).

    python3 scripts/integration/ws2_run.py --workspace 3 LOG -- \\
        python3 scripts/integration/test-tray-relaunch.py
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
BTN_RIGHT, KEY_ESC = 273, 1
FAILURES = ("TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type")


def inspect(session: H.Session, name: str) -> dict:
    return next(e for e in json.loads(session.ipc("bottomHub", "inspect").stdout) if e["screen"] == name)


def tray_rect(session: H.Session) -> list[float]:
    return [float(v) for v in session.ipc("bottomHub", "trayButton").stdout.split()]


def provider(session: H.Session, app_id: str) -> subprocess.Popen:
    return subprocess.Popen([sys.executable, str(FIXTURE), "--instances", "1", "--id", app_id], env=session.env(),
                            stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT, start_new_session=True)


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    if missing := H.missing_tools():
        print(f"SKIP: faltan {', '.join(missing)}")
        return 0
    with tempfile.TemporaryDirectory(prefix="cz30-tray-relaunch-") as temporary:
        session = H.Session(Path(temporary))
        apps: list[subprocess.Popen] = []
        try:
            session.start(outputs=2)
            name = session.headless()[0]
            session.focus_monitor(name)

            # An app shows in the tray and quits; no popout has opened yet.
            apps.append(provider(session, "cortetsu-first"))
            H.wait_for(lambda: len(tray_rect(session)) == 4, "primer icono en la bandeja")
            time.sleep(1.0)
            apps[0].terminate()
            apps[0].wait(10)
            H.wait_for(lambda: len(tray_rect(session)) != 4, "bandeja vacía al irse la aplicación")
            assert not inspect(session, name)["open"]

            # The next app's menu opens by a real right click.
            apps.append(provider(session, "cortetsu-second"))
            rect = H.settled(lambda: tray_rect(session) if len(tray_rect(session)) == 4 else None, "segundo icono")
            x, y = int(rect[0] + rect[2] / 2), int(rect[1] + rect[3] / 2)
            session.move(x, y)
            time.sleep(0.05)
            session.send(f"button {BTN_RIGHT} 1")
            time.sleep(0.03)
            session.send(f"button {BTN_RIGHT} 0")
            H.wait_for(lambda: inspect(session, name)["open"], "popout abierto por el clic derecho")
            time.sleep(0.6)
            state = inspect(session, name)
            tray = state["tray"]
            assert tray["shouldBeActive"] and tray["menuContentHeight"] > 0, \
                f"el popout no tiene el menú de la aplicación: popup={state['popup']} tray={tray}"
            assert state["popup"] == f"traymenu{tray['itemKey']}", (state["popup"], tray["itemKey"])

            session.tap(KEY_ESC)
            H.wait_for(lambda: not inspect(session, name)["open"], "menú cerrado con Escape")
            assert not inspect(session, name)["keyboardHeld"], "el Hub retiene el teclado tras cerrar"

            log = (session.logs / "qs.log").read_text(errors="replace")
            bad = [line for line in log.splitlines() if any(marker in line for marker in FAILURES)]
            assert not bad, "\n".join(bad[:12])
            assert not session.crash_reports(), "Quickshell se cayó durante la prueba"
        finally:
            for app in apps:
                if app.poll() is None:
                    app.terminate()
                    app.wait(10)
            session.stop()
    print("PASS: una aplicación que entra y sale de la bandeja antes del primer popout no desplaza las claves: "
          "el menú de la siguiente abre con su contenido")
    return 0


if __name__ == "__main__":
    sys.exit(main())
