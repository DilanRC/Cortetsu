#!/usr/bin/env python3
"""Runtime check that the notification snapshot follows the live server.

CortetsuNotifications (BottomHub count, sidebar history) and the
cortetsu-notifications CLI work on cortetsu/notifs.json, but nothing wrote it
since Notifs.qml became first-party, so the count stayed 0 and dismiss/clear
never reached a visible notification. This drives the real Notifs.qml,
NotifData.qml and CortetsuNotifications.qml in a nested Hyprland on a private
D-Bus session bus, so the live shell's notification server is never touched.
"""
import json
import os
import shutil
import subprocess
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

SHELL_QML = """
import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    IpcHandler {
        target: "harness"
        function state(): string {
            return JSON.stringify({
                live: Notifs.list.filter(item => !item.closed).map(item => item.summary),
                facadeCount: CortetsuNotifications.count,
                facadeSummaries: CortetsuNotifications.history.map(entry => entry.summary)
            })
        }
    }
}
"""

STUBS = {
    "modules/CortetsuConfig.qml": "pragma Singleton\nimport Quickshell\nSingleton { property bool suppressNotificationsInFullscreen: false }\n",
    "modules/CortetsuHypr.qml": "pragma Singleton\nimport Quickshell\nSingleton { readonly property var monitors: ({ values: [] }) }\n",
    "modules/CortetsuShellState.qml": "pragma Singleton\nimport Quickshell\nSingleton { function anySidebarOpen(): bool { return false } }\n",
}

COPIES = ("services/Notifs.qml", "services/NotifData.qml", "modules/CortetsuNotifications.qml",
          "modules/CortetsuShortcut.qml")


def wait_for(predicate, what: str, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = predicate()
            if last:
                return last
        except (AssertionError, ValueError, subprocess.SubprocessError):
            pass
        time.sleep(0.1)
    raise AssertionError(f"timeout esperando: {what} (último valor: {last!r})")


def main() -> int:
    parent = os.environ.get("WAYLAND_DISPLAY")
    if not parent:
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    for tool in ("qs", "Hyprland", "dbus-daemon", "notify-send"):
        if not shutil.which(tool):
            print(f"SKIP: falta {tool}")
            return 0
    parent_socket = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)

    # A short runtime path: Hyprland refuses IPC sockets with long paths.
    with tempfile.TemporaryDirectory(prefix="czn", dir="/tmp") as tmp:
        base = Path(tmp)
        runtime = base / "r"
        runtime.mkdir(mode=0o700)
        (base / "cfg/hypr").mkdir(parents=True)
        (base / "cfg/hypr/hyprland.lua").write_text("hl.config({ misc = { disable_hyprland_logo = true } })\n")
        shell = base / "shell"
        for folder in ("modules", "services"):
            (shell / folder).mkdir(parents=True)
        (shell / "shell.qml").write_text(SHELL_QML, encoding="utf-8")
        for relative in COPIES:
            shutil.copy(ROOT / "cortetsu" / relative, shell / relative)
        for relative, text in STUBS.items():
            (shell / relative).write_text(text, encoding="utf-8")
        history = base / "state/cortetsu/notifs.json"

        env = {"HOME": str(base), "PATH": os.environ["PATH"], "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(base / "cfg"), "XDG_STATE_HOME": str(base / "state")}
        bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], env=env,
                               stdout=subprocess.PIPE, text=True)
        env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=dict(env, WAYLAND_DISPLAY=parent_socket),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log = (base / "qs.log").open("w")
        proc = None
        try:
            wait_for(lambda: (runtime / "wayland-1").exists(), "Hyprland anidado")
            nested = dict(env, WAYLAND_DISPLAY="wayland-1", QT_QPA_PLATFORM="wayland")

            def start():
                started = subprocess.Popen(["qs", "-p", str(shell), "-n"], env=nested, stdout=log,
                                           stderr=subprocess.STDOUT)
                wait_for(lambda: state_of(started) is not None, "shell de prueba")
                return started

            def state_of(target) -> dict | None:
                assert target.poll() is None, "el shell de prueba terminó"
                result = subprocess.run(["qs", "ipc", "--pid", str(target.pid), "call", "harness", "state"],
                                        capture_output=True, text=True, timeout=10, env=nested)
                return json.loads(result.stdout) if result.returncode == 0 else None

            def state() -> dict:
                return state_of(proc)

            def snapshot() -> list:
                return json.loads(history.read_text()) if history.exists() else []

            def notify(summary: str) -> None:
                subprocess.run(["notify-send", "-a", "Prueba", "-t", "0", summary, "cuerpo"], env=nested,
                               check=True, timeout=10)

            def cli(*args: str) -> None:
                subprocess.run([str(ROOT / "cortetsu/bin/cortetsu-notifications"), *args], env=nested,
                               check=True, timeout=10, capture_output=True)

            proc = start()
            notify("Uno")
            notify("Dos")
            wait_for(lambda: sorted(entry["summary"] for entry in snapshot()) == ["Dos", "Uno"],
                     "las notificaciones vivas en notifs.json")
            wait_for(lambda: state()["facadeCount"] == 2, "CortetsuNotifications.count == 2")
            entry = next(entry for entry in snapshot() if entry["summary"] == "Uno")
            assert {"id", "summary", "body", "appName", "time"} <= entry.keys(), entry

            cli("dismiss", str(entry["id"]))
            wait_for(lambda: state()["live"] == ["Dos"], "dismiss del CLI cierra la notificación viva")
            wait_for(lambda: state()["facadeCount"] == 1, "el contador baja a 1")

            # A notification that arrives after the last save is not in the file
            # yet; a stale snapshot must not close it.
            notify("Tres")
            wait_for(lambda: sorted(state()["live"]) == ["Dos", "Tres"], "la nueva notificación sigue viva")
            wait_for(lambda: state()["facadeCount"] == 2, "el contador incluye la nueva")

            proc.terminate()
            proc.wait(timeout=10)
            proc = start()
            wait_for(lambda: sorted(state()["live"]) == ["Dos", "Tres"], "el historial sobrevive al reinicio")
            assert sorted(entry["summary"] for entry in snapshot()) == ["Dos", "Tres"], snapshot()

            cli("clear")
            wait_for(lambda: state()["live"] == [], "clear del CLI vacía el servidor vivo")
            wait_for(lambda: state()["facadeCount"] == 0 and snapshot() == [], "contador y fichero en 0")

            # clear inside the save debounce still reaches a notification the
            # snapshot has not listed yet.
            notify("Cuatro")
            wait_for(lambda: state()["live"] == ["Cuatro"], "la notificación recién llegada")
            cli("clear")
            wait_for(lambda: state()["live"] == [], "clear cierra lo que llegó tras el último guardado")
            time.sleep(1)
            assert snapshot() == [] and state()["live"] == [], (snapshot(), state())
        except AssertionError:
            log.flush()
            print((base / "qs.log").read_text()[-3000:])
            raise
        finally:
            if proc and proc.poll() is None:
                proc.terminate()
                proc.wait(timeout=10)
            compositor.terminate()
            try:
                compositor.wait(timeout=10)
            except subprocess.TimeoutExpired:
                compositor.kill()
            bus.terminate()
            bus.wait(timeout=10)
    print("PASS: notifs.json follows the live server; CLI dismiss/clear reach it; history survives a restart")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
