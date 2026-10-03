#!/usr/bin/env python3
"""Runtime check of the lock release path inside a nested Hyprland.

Drives the real Pam.qml against a real WlSessionLock and real PamContext. The
session lock belongs to a throwaway nested compositor, so the desktop session
is never locked. PAM stacks are pam_permit/pam_deny: no password is involved.

Usage: test-cortetsu-lock-runtime.py [--pam-qml PATH]
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_PAM = ROOT / "cortetsu/base/modules/lock/Pam.qml"

SHELL_QML = """
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "modules/lock"

ShellRoot {
    id: root
    property int successes: 0

    WlSessionLock {
        id: sessionLock
        signal unlock
        WlSessionLockSurface { color: "black" }
    }

    Pam { id: pam; lock: sessionLock }

    Connections {
        target: pam
        function onAuthenticationSucceeded(): void { root.successes += 1 }
    }

    IpcHandler {
        target: "harness"
        function lock(): void { sessionLock.locked = true }
        function submit(): void { pam.passwd.start() }
        function release(): void { pam.releaseAfterSuccess() }
        function signalUnlock(): void { sessionLock.unlock() }
        function state(): string {
            return JSON.stringify({
                locked: sessionLock.locked,
                secure: sessionLock.secure,
                successes: root.successes,
                successPending: pam.successPending,
                pamState: pam.state,
                active: pam.passwd.active
            });
        }
    }
}
"""

CONFIG_STUB = """pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool lockEnableFprint: false
    property int lockMaxFprintTries: 3
    property bool lockEnableHowdy: false
    property int lockMaxHowdyTries: 3
    property bool lockTriggerHowdyOnWake: false
}
"""

SESSION_STUB = """pragma Singleton
import QtQuick
import Quickshell

Singleton {
    signal resumed
}
"""

PAM_FAILED = 3  # Pam.PamState.Failed


def build_shell(base: Path, pam_qml: Path, module: str) -> Path:
    shell = base / f"shell-{module}"
    (shell / "modules/lock").mkdir(parents=True)
    (shell / "services").mkdir()
    (shell / "assets/pam.d").mkdir(parents=True)
    (shell / "shell.qml").write_text(SHELL_QML, encoding="utf-8")
    shutil.copy(pam_qml, shell / "modules/lock/Pam.qml")
    (shell / "modules/CortetsuConfig.qml").write_text(CONFIG_STUB, encoding="utf-8")
    (shell / "services/CortetsuSession.qml").write_text(SESSION_STUB, encoding="utf-8")
    for name in ("passwd", "fprint", "howdy"):
        (shell / "assets/pam.d" / name).write_text(
            f"#%PAM-1.0\nauth    required    pam_{module}.so\n", encoding="utf-8")
    return shell


def wait_for(predicate, what: str, timeout: float = 15.0):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    raise AssertionError(f"timeout esperando: {what}")


class Shell:
    def __init__(self, shell_dir: Path, env: dict, log: Path):
        self.env = env
        self.log = log.open("w")
        self.proc = subprocess.Popen(["qs", "-p", str(shell_dir)], env=env,
                                     stdout=self.log, stderr=subprocess.STDOUT)
        wait_for(self._ready, "IPC del shell de prueba")

    def _call(self, fn: str) -> subprocess.CompletedProcess:
        return subprocess.run(["qs", "ipc", "--pid", str(self.proc.pid), "call", "harness", fn],
                              env=self.env, capture_output=True, text=True, timeout=10)

    def _ready(self) -> bool:
        assert self.proc.poll() is None, "el shell de prueba terminó al arrancar"
        return self._call("state").returncode == 0

    def call(self, fn: str) -> None:
        result = self._call(fn)
        assert result.returncode == 0, f"{fn}: {result.stderr}"

    def state(self) -> dict:
        result = self._call("state")
        assert result.returncode == 0, result.stderr
        return json.loads(result.stdout)

    def until(self, what: str, **expected) -> dict:
        def matched():
            state = self.state()
            return state if all(state[key] == value for key, value in expected.items()) else None

        return wait_for(matched, f"{what} {expected}")

    def stop(self) -> None:
        self.proc.terminate()
        try:
            self.proc.wait(5)
        except subprocess.TimeoutExpired:
            self.proc.kill()
        self.log.close()


def start_compositor(base: Path):
    runtime = Path(os.environ["XDG_RUNTIME_DIR"])
    before = {p.name for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")}
    config = base / "hyprland.lua"
    config.write_text("", encoding="utf-8")
    env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
    log = (base / "hyprland.log").open("w")
    proc = subprocess.Popen(["Hyprland", "-c", str(config)], env=env, stdout=log, stderr=subprocess.STDOUT)

    def new_socket():
        assert proc.poll() is None, "el Hyprland anidado terminó al arrancar"
        fresh = {p.name for p in runtime.glob("wayland-*") if not p.name.endswith(".lock")} - before
        return next(iter(fresh), None)

    try:
        socket = wait_for(new_socket, "socket Wayland del compositor anidado")
    except BaseException:
        proc.kill()
        raise
    return proc, socket


def scenario_permit(shell: Shell) -> None:
    shell.call("lock")
    shell.until("bloqueo seguro", locked=True, secure=True)

    shell.call("signalUnlock")
    shell.call("release")
    time.sleep(0.5)
    state = shell.state()
    assert state["locked"], "una ruta sin autenticar liberó el bloqueo"

    for cycle in (1, 2):
        shell.call("submit")
        state = shell.until("éxito PAM", successes=cycle, successPending=True)
        assert state["locked"], "el bloqueo se liberó antes de la transición"
        shell.call("release")
        shell.until("desbloqueo tras autenticar", locked=False, successPending=False)
        shell.call("release")  # idempotente
        if cycle == 1:
            shell.call("lock")
            state = shell.until("segundo bloqueo", locked=True, secure=True)
            assert not state["successPending"], "el éxito anterior sobrevivió al nuevo bloqueo"


def scenario_deny(shell: Shell) -> None:
    shell.call("lock")
    shell.until("bloqueo seguro", locked=True, secure=True)
    for _ in range(3):
        shell.call("submit")
        shell.until("rechazo PAM", pamState=PAM_FAILED, active=False)
        shell.call("release")
        state = shell.state()
        assert state["locked"] and not state["successPending"] and state["successes"] == 0, state


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pam-qml", type=Path, default=DEFAULT_PAM)
    args = parser.parse_args()

    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    for tool in ("Hyprland", "qs"):
        if not shutil.which(tool):
            print(f"SKIP: falta {tool}")
            return 0

    with tempfile.TemporaryDirectory(prefix="cortetsu-lock-") as tmp:
        base = Path(tmp)
        compositor, socket = start_compositor(base)
        env = {k: v for k, v in os.environ.items() if k != "HYPRLAND_INSTANCE_SIGNATURE"}
        env["WAYLAND_DISPLAY"] = socket
        env["QT_QPA_PLATFORM"] = "wayland"
        try:
            for module, scenario in (("permit", scenario_permit), ("deny", scenario_deny)):
                shell = Shell(build_shell(base, args.pam_qml, module), env, base / f"qs-{module}.log")
                try:
                    scenario(shell)
                except BaseException:
                    shell.log.flush()
                    sys.stderr.write((base / f"qs-{module}.log").read_text(errors="replace")[-3000:])
                    raise
                finally:
                    shell.stop()
        finally:
            compositor.terminate()
            try:
                compositor.wait(5)
            except subprocess.TimeoutExpired:
                compositor.kill()

    print("PASS: el bloqueo solo se libera tras autenticación PAM válida, sobrevive a rechazos y a rutas sin autenticar")
    return 0


if __name__ == "__main__":
    sys.exit(main())
