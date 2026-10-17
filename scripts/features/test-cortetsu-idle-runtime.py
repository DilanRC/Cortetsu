#!/usr/bin/env python3
"""Runtime check of the idle policy against the real IdleMonitors.qml.

Runs inside a nested Hyprland, so nobody's typing resets the idle timers. The
lock controller is a stand-in with the surface of modules/lock/Lock.qml
(requestLock, lockReady, lock.secure). busctl and systemctl are fakes on PATH:
logind is asked nothing and the machine can never be suspended. The Hyprland
singleton records dispatches instead of running them.
"""
import contextlib
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))
from nested_gpu import MESA_ONLY, compositor_env  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]

SHELL_QML = """
import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    Scope {
        id: lock
        property alias lock: sessionLock
        readonly property bool lockReady: sessionLock.locked
        function requestLock(): void { sessionLock.locked = true; sessionLock.secure = true; }
        QtObject { id: sessionLock; property bool locked: false; property bool secure: false }
    }

    IdleMonitors { id: monitors; lock: lock }

    IpcHandler {
        target: "harness"
        function idleLock(): void { monitors.handleIdleAction("lock") }
        function sleep(): void { CortetsuSession.aboutToSleep() }
        function unlock(): void { sessionLock.locked = false; sessionLock.secure = false; }
        function setLockBeforeSleep(value: bool): void { CortetsuConfig.idleLockBeforeSleep = value }
        function configure(json: string): void {
            const values = JSON.parse(json);
            for (const key of Object.keys(values)) CortetsuConfig[key] = values[key];
        }
        function setFullscreen(value: bool): void { CortetsuHypr.fullscreen = value ? 2 : 0 }
        function setExternal(value: bool): void { CortetsuHypr.external = value }
        function setKeepAwake(value: bool): void { CortetsuIdleInhibitor.enabled = value }
        function state(): string {
            return JSON.stringify({ locked: lock.lockReady, dispatched: CortetsuHypr.dispatched,
                                    canSuspend: CortetsuSession.canSuspend })
        }
    }
}
"""

CONFIG_STUB = """pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool idleInhibitWhenAudio: false
    property bool idleInhibitWhenCharging: false
    property bool idleLockBeforeSleep: true
    property var idleTimeouts: []
    property bool idleSuspendOnBatteryOnly: true
    property bool idleInhibitWhenFullscreen: true
}
"""

HYPR_STUB = """pragma Singleton
import QtQuick
import Quickshell

Singleton {
    readonly property bool usingLua: true
    property var dispatched: []
    property int fullscreen: 0
    property bool external: false
    readonly property var monitors: ({ values: [
        { name: "eDP-1", focused: true, activeWorkspace: { toplevels: { values: [{ lastIpcObject: { fullscreen: fullscreen } }] } } },
        ...(external ? [{ name: "HDMI-A-1", focused: false, activeWorkspace: { toplevels: { values: [] } } }] : [])
    ] })
    function dispatch(request: string): void { dispatched = [...dispatched, request]; }
}
"""

PLAYERS_STUB = """pragma Singleton
import Quickshell

Singleton { property var list: [] }
"""

POWER_STUB = """pragma Singleton
import Quickshell

Singleton { property bool onBattery: true }
"""

FAKE_BUSCTL = """#!/bin/sh
echo 's "yes"'
"""

FAKE_SYSTEMCTL = """#!/bin/sh
echo "$*" >> "$FAKE_SYSTEMCTL_LOG"
"""


def wait_for(predicate, what: str, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"timeout esperando: {what}")


def stays(predicate, what: str, seconds: float):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        assert predicate(), what
        time.sleep(0.1)


def main() -> int:
    parent = os.environ.get("WAYLAND_DISPLAY")
    if not parent:
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    for tool in ("qs", "Hyprland", "systemd-inhibit"):
        if not shutil.which(tool):
            print(f"SKIP: falta {tool}")
            return 0
    parent_socket = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)

    # A short runtime path: Hyprland refuses IPC sockets with long paths.
    with tempfile.TemporaryDirectory(prefix="czi", dir="/tmp") as tmp:
        base = Path(tmp)
        runtime = base / "r"
        runtime.mkdir(mode=0o700)
        (base / "cfg/hypr").mkdir(parents=True)
        (base / "cfg/hypr/hyprland.lua").write_text("hl.config({ misc = { disable_hyprland_logo = true } })\n")
        tools = base / "bin"
        tools.mkdir()
        for name, text in (("busctl", FAKE_BUSCTL), ("systemctl", FAKE_SYSTEMCTL)):
            (tools / name).write_text(text)
            (tools / name).chmod(0o755)
        calls = base / "systemctl.log"
        calls.write_text("")

        shell = base / "shell"
        (shell / "modules").mkdir(parents=True)
        (shell / "services").mkdir()
        (shell / "shell.qml").write_text(SHELL_QML, encoding="utf-8")
        for source, target in (("modules/IdleMonitors.qml", "modules"), ("modules/CortetsuIdleInhibitor.qml", "modules"),
                               ("modules/CortetsuShortcut.qml", "modules"), ("services/CortetsuSession.qml", "services")):
            shutil.copy(ROOT / "cortetsu" / source, shell / target)
        (shell / "modules/CortetsuConfig.qml").write_text(CONFIG_STUB, encoding="utf-8")
        (shell / "modules/CortetsuHypr.qml").write_text(HYPR_STUB, encoding="utf-8")
        (shell / "services/Players.qml").write_text(PLAYERS_STUB, encoding="utf-8")
        (shell / "services/CortetsuPower.qml").write_text(POWER_STUB, encoding="utf-8")

        env = {"HOME": str(base), "PATH": f"{tools}:{os.environ['PATH']}", "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(base / "cfg"), "FAKE_SYSTEMCTL_LOG": str(calls), **MESA_ONLY}
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent_socket), base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        log = (base / "qs.log").open("w")
        proc = None
        try:
            wait_for(lambda: (runtime / "wayland-1").exists(), "Hyprland anidado")
            nested = dict(env, WAYLAND_DISPLAY="wayland-1", QT_QPA_PLATFORM="wayland")
            # Own process group: the shell's helpers (systemd-inhibit holding a
            # real logind delay lock, dbus-monitor) are not in a cgroup here and
            # outlive a plain terminate of qs.
            proc = subprocess.Popen(["qs", "-p", str(shell), "-n"], env=nested, stdout=log, stderr=subprocess.STDOUT,
                                    start_new_session=True)

            def call(fn: str, *args: str) -> str:
                result = subprocess.run(["qs", "ipc", "--pid", str(proc.pid), "call", "harness", fn, *args],
                                        capture_output=True, text=True, timeout=10, env=nested)
                assert result.returncode == 0, f"{fn}: {result.stderr}"
                return result.stdout

            def ready() -> bool:
                assert proc.poll() is None, "el shell de prueba terminó al arrancar"
                return subprocess.run(["qs", "ipc", "--pid", str(proc.pid), "call", "harness", "state"],
                                      capture_output=True, timeout=10, env=nested).returncode == 0

            def state() -> dict:
                return json.loads(call("state"))

            def locked() -> bool:
                return state()["locked"]

            def inhibitor() -> bool:
                children = subprocess.run(["pgrep", "-P", str(proc.pid), "-f", "systemd-inhibit --what=sleep --mode=delay"],
                                          capture_output=True, text=True).stdout.split()
                return bool(children)

            def configure(**values) -> None:
                call("configure", json.dumps(values))

            wait_for(ready, "IPC del shell de prueba")
            wait_for(lambda: state()["canSuspend"] == "yes", "capacidades de logind")

            # Lock before sleep holds a delay inhibitor only while unlocked.
            wait_for(inhibitor, "retardo de suspensión mientras la sesión está desbloqueada")
            call("idleLock")
            assert locked(), "la acción idle 'lock' no bloqueó"
            wait_for(lambda: not inhibitor(), "liberar el retardo con la sesión bloqueada")
            call("unlock")
            wait_for(inhibitor, "recuperar el retardo tras desbloquear")
            call("sleep")
            assert locked(), "PrepareForSleep no bloqueó con el ajuste activo"
            call("unlock")
            call("setLockBeforeSleep", "false")
            wait_for(lambda: not inhibitor(), "sin retardo con el ajuste desactivado")
            call("sleep")
            assert not locked(), "PrepareForSleep bloqueó con el ajuste desactivado"
            call("setLockBeforeSleep", "true")

            # idleTimeouts is in milliseconds: 2000 locks after two seconds.
            # Passed through unconverted, IdleMonitor would wait 2000 seconds.
            lock_after_2s = [{"enabled": True, "timeout": 2000, "idleAction": "lock"}]
            configure(idleTimeouts=lock_after_2s)
            wait_for(locked, "bloqueo por inactividad a los 2 s", timeout=8)
            call("unlock")

            # A fullscreen window holds the screen and sleep, never the lock.
            screen_off_3s = [{"timeout": 3000, "idleAction": "dpms"}]
            suspend_3s = [{"timeout": 3000, "idleAction": "suspend"}]
            call("setFullscreen", "true")
            configure(idleTimeouts=[])
            configure(idleTimeouts=lock_after_2s + screen_off_3s)
            wait_for(locked, "bloqueo con pantalla completa", timeout=8)
            stays(lambda: not state()["dispatched"], "pantalla completa no frenó el apagado", 2.5)
            call("unlock")
            call("setFullscreen", "false")

            def logind_inhibitors() -> list[str]:
                listing = subprocess.run(["systemd-inhibit", "--list", "--no-pager", "--no-legend"],
                                         capture_output=True, text=True).stdout
                return sorted(line for line in listing.splitlines() if line.strip())

            before = logind_inhibitors()
            call("setKeepAwake", "true")
            configure(idleTimeouts=[])
            configure(idleTimeouts=lock_after_2s + screen_off_3s)
            stays(lambda: not locked() and not state()["dispatched"], "keep-awake no frenó la inactividad", 4.5)
            assert logind_inhibitors() == before, "keep-awake no debe añadir inhibidores de logind"
            call("setKeepAwake", "false")

            # Screen off after its own timeout.
            configure(idleTimeouts=[])
            configure(idleTimeouts=screen_off_3s)
            wait_for(lambda: 'hl.dsp.dpms({ action = "off" })' in state()["dispatched"], "apagar pantalla", timeout=8)
            configure(idleTimeouts=[])

            # Idle suspend: never docked to an external screen.
            call("setExternal", "true")
            configure(idleTimeouts=suspend_3s)
            stays(lambda: "suspend" not in calls.read_text(), "suspendió con pantalla externa", 4.5)
            call("setExternal", "false")
            wait_for(lambda: calls.read_text().splitlines() == ["suspend"], "suspensión por inactividad", timeout=8)
            configure(idleTimeouts=[])
        except BaseException:
            log.flush()
            sys.stderr.write((base / "qs.log").read_text(errors="replace")[-3000:])
            raise
        finally:
            if proc:
                # An empty group (qs crashed with no helpers left) raises
                # ProcessLookupError; it must not hide the test's own failure.
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(proc.pid, signal.SIGTERM)
                try:
                    proc.wait(5)
                except subprocess.TimeoutExpired:
                    pass
                with contextlib.suppress(ProcessLookupError):
                    os.killpg(proc.pid, signal.SIGKILL)
            log.close()
            compositor.terminate()
            try:
                compositor.wait(10)
            except subprocess.TimeoutExpired:
                compositor.kill()

    print("PASS: bloqueo, apagado y suspensión por inactividad siguen la política; la pantalla completa frena "
          "apagado y suspensión pero no el bloqueo; keep-awake frena todo sin inhibir logind; PrepareForSleep bloquea")
    return 0


if __name__ == "__main__":
    sys.exit(main())
