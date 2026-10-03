#!/usr/bin/env python3
"""Runtime check of idle and sleep locking against the real IdleMonitors.qml.

The lock controller is a stand-in with the exact surface of modules/lock/Lock.qml
(requestLock, lockReady, lock.secure and no writable `locked`), so the session is
never locked and nothing is suspended. The sleep signal is emitted by hand.
"""
import json
import os
import shutil
import subprocess
import sys
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
        function state(): string { return JSON.stringify({ locked: lock.lockReady }) }
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
    property list<var> idleTimeouts: []
}
"""

HYPR_STUB = """pragma Singleton
import Quickshell

Singleton { function dispatch(request: string): void {} }
"""

PLAYERS_STUB = """pragma Singleton
import Quickshell

Singleton { property var list: [] }
"""

POWER_STUB = """pragma Singleton
import Quickshell

Singleton { property bool onBattery: true }
"""


def wait_for(predicate, what: str, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"timeout esperando: {what}")


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland")
        return 0
    for tool in ("qs", "systemd-inhibit"):
        if not shutil.which(tool):
            print(f"SKIP: falta {tool}")
            return 0

    with tempfile.TemporaryDirectory(prefix="cortetsu-idle-") as tmp:
        shell = Path(tmp)
        (shell / "modules").mkdir()
        (shell / "services").mkdir()
        (shell / "shell.qml").write_text(SHELL_QML, encoding="utf-8")
        shutil.copy(ROOT / "cortetsu/modules/IdleMonitors.qml", shell / "modules/IdleMonitors.qml")
        shutil.copy(ROOT / "cortetsu/services/CortetsuSession.qml", shell / "services/CortetsuSession.qml")
        (shell / "modules/CortetsuConfig.qml").write_text(CONFIG_STUB, encoding="utf-8")
        (shell / "modules/CortetsuHypr.qml").write_text(HYPR_STUB, encoding="utf-8")
        (shell / "services/Players.qml").write_text(PLAYERS_STUB, encoding="utf-8")
        (shell / "services/CortetsuPower.qml").write_text(POWER_STUB, encoding="utf-8")
        log = (shell / "qs.log").open("w")
        proc = subprocess.Popen(["qs", "-p", str(shell), "-n"], stdout=log, stderr=subprocess.STDOUT)

        def call(fn: str, *args: str) -> str:
            result = subprocess.run(["qs", "ipc", "--pid", str(proc.pid), "call", "harness", fn, *args],
                                    capture_output=True, text=True, timeout=10)
            assert result.returncode == 0, f"{fn}: {result.stderr}"
            return result.stdout

        def ready() -> bool:
            assert proc.poll() is None, "el shell de prueba terminó al arrancar"
            return subprocess.run(["qs", "ipc", "--pid", str(proc.pid), "call", "harness", "state"],
                                  capture_output=True, timeout=10).returncode == 0

        def locked() -> bool:
            return json.loads(call("state"))["locked"]

        def inhibitor() -> bool:
            children = subprocess.run(["pgrep", "-P", str(proc.pid), "-f", "systemd-inhibit --what=sleep --mode=delay"],
                                      capture_output=True, text=True).stdout.split()
            return bool(children)

        try:
            wait_for(ready, "IPC del shell de prueba")
            wait_for(inhibitor, "retardo de suspensión mientras la sesión está desbloqueada")

            call("idleLock")
            assert locked(), "la acción idle 'lock' no bloqueó"
            wait_for(lambda: not inhibitor(), "liberar el retardo con la sesión bloqueada")

            call("unlock")
            wait_for(inhibitor, "recuperar el retardo tras desbloquear")
            call("sleep")
            assert locked(), "PrepareForSleep no bloqueó con el ajuste activo"
            wait_for(lambda: not inhibitor(), "liberar el retardo antes de dormir")

            call("unlock")
            call("setLockBeforeSleep", "false")
            wait_for(lambda: not inhibitor(), "sin retardo con el ajuste desactivado")
            call("sleep")
            assert not locked(), "PrepareForSleep bloqueó con el ajuste desactivado"
        except BaseException:
            log.flush()
            sys.stderr.write((shell / "qs.log").read_text(errors="replace")[-3000:])
            raise
        finally:
            proc.terminate()
            try:
                proc.wait(5)
            except subprocess.TimeoutExpired:
                proc.kill()
            log.close()

    print("PASS: idle y PrepareForSleep bloquean por requestLock y el retardo de suspensión sigue al estado del bloqueo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
