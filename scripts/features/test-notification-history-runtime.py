#!/usr/bin/env python3
"""Production notification QML and native owner on a private offscreen session.

No compositor or existing desktop is used. A test-only process barrier delays
one native merge so dismissal/clear and a later arrival can be interleaved
without replacing the owner's merge implementation or its returned JSON.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]

SHELL_QML = r'''
import QtQuick
import Quickshell
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    readonly property bool initialized: Notifs.loaded && CortetsuNotifications.loaded
    IpcHandler {
        target: "harness"
        function state(): string {
            return JSON.stringify({
                live: Notifs.notClosed().map(item => item.summary),
                popups: Notifs.popups().map(item => item.summary),
                facadeCount: CortetsuNotifications.count,
                facadeSummaries: CortetsuNotifications.history.map(entry => entry.summary),
                dnd: Notifs.dnd, dndReady: Notifs.dndStorageReady,
                facadeDnd: CortetsuNotifications.dnd, statusReady: CortetsuNotifications.statusReady,
                loaded: Notifs.loaded, historyReady: CortetsuNotifications.historyReady,
                writing: Notifs.snapshotInFlight, writeError: Notifs.lastWriteError,
                clearRevision: Notifs.clearState?.revision ?? -1,
                clearPending: Notifs.clearState?.pending ?? false
            });
        }
        function toggleDnd(): void { CortetsuNotifications.toggleDnd(); }
        function clear(): void { CortetsuNotifications.clear(); }
    }
}
'''

STUBS = {
    "modules/CortetsuConfig.qml": "pragma Singleton\nimport Quickshell\nSingleton { property bool suppressNotificationsInFullscreen: false }\n",
    "modules/CortetsuHypr.qml": "pragma Singleton\nimport Quickshell\nSingleton { readonly property var monitors: ({ values: [] }) }\n",
    "modules/CortetsuShellState.qml": "pragma Singleton\nimport Quickshell\nSingleton { function anySidebarOpen(): bool { return false } }\n",
    # Global compositor shortcuts are unrelated to the private D-Bus server.
    "modules/CortetsuShortcut.qml": "import QtQuick\nQtObject { property string name; property string description; signal pressed() }\n",
}
COPIES = ("services/Notifs.qml", "services/NotifData.qml", "modules/CortetsuNotifications.qml",
          "modules/CortetsuNotificationModel.js")

WRAPPER = r'''
import os, subprocess, sys, time
from pathlib import Path
native = os.environ['NOTIFICATION_NATIVE']
args = sys.argv[1:]
if args != ['merge']:
    os.execv(native, [native, *args])
payload = sys.stdin.buffer.read(1024 * 1024 + 1)
base = Path(os.environ['NOTIFICATION_FIXTURE'])
gate = base / 'hold-next-merge'
if gate.exists():
    gate.unlink()
    (base / 'merge-entered').write_bytes(payload)
    deadline = time.monotonic() + 6
    while not (base / 'release-merge').exists():
        if time.monotonic() >= deadline:
            print('fixture merge barrier timed out', file=sys.stderr)
            sys.exit(2)
        time.sleep(.02)
    (base / 'release-merge').unlink()
result = subprocess.run([native, *args], input=payload, capture_output=True, timeout=6)
sys.stdout.buffer.write(result.stdout)
sys.stderr.buffer.write(result.stderr)
sys.exit(result.returncode)
'''


def wait_for(predicate, what: str, timeout: float = 12.0):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            last = predicate()
            if last:
                return last
        except (AssertionError, ValueError, FileNotFoundError, subprocess.SubprocessError):
            pass
        time.sleep(0.05)
    raise AssertionError(f"timeout esperando: {what} (último valor: {last!r})")


def native_binary() -> Path:
    requested = os.environ.get("CORTETSU_NOTIFICATIONS_BINARY")
    candidates = [Path(requested)] if requested else [
        ROOT / "dist/native/cortetsu-notifications-rs",
        ROOT / "cortetsu/notification-helper/target/release/cortetsu-notifications-rs",
        ROOT / "cortetsu/notification-helper/target/debug/cortetsu-notifications-rs",
    ]
    for path in candidates:
        if path.is_file() and os.access(path, os.X_OK):
            return path.resolve()
    raise RuntimeError("Build the native notification owner before running this QML gate")


def stop(process):
    if process is None:
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
    try:
        process.wait(timeout=4)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        process.wait(timeout=4)


def main() -> int:
    quickshell = shutil.which("quickshell") or shutil.which("qs")
    if not quickshell or any(not shutil.which(tool) for tool in ("dbus-daemon", "notify-send")):
        raise RuntimeError("This runtime gate requires Quickshell, dbus-daemon and notify-send")
    native = native_binary()
    with tempfile.TemporaryDirectory(prefix="czn", dir="/tmp") as temporary:
        base = Path(temporary)
        runtime = base / "r"
        runtime.mkdir(mode=0o700)
        shell = base / "shell"
        for folder in ("modules", "services"):
            (shell / folder).mkdir(parents=True)
        (shell / "shell.qml").write_text(SHELL_QML)
        for relative in COPIES:
            shutil.copyfile(ROOT / "cortetsu" / relative, shell / relative)
        for relative, text in STUBS.items():
            (shell / relative).write_text(text)
        binaries = base / "bin"
        binaries.mkdir()
        wrapper = binaries / "cortetsu-notifications"
        wrapper.write_text(f"#!{sys.executable}\n" + WRAPPER)
        wrapper.chmod(0o700)
        history = base / "state/cortetsu/notifs.json"
        status = base / "state/cortetsu/notification-status.json"
        env = {**os.environ, "HOME": str(base), "PATH": f"{binaries}:{os.environ['PATH']}", "LANG": "C.UTF-8",
            "XDG_RUNTIME_DIR": str(runtime), "XDG_CONFIG_HOME": str(base / "cfg"),
            "XDG_STATE_HOME": str(base / "state"), "XDG_CACHE_HOME": str(base / "cache"),
            "QT_QPA_PLATFORM": "offscreen", "NOTIFICATION_NATIVE": str(native), "NOTIFICATION_FIXTURE": str(base)}
        env.pop("WAYLAND_DISPLAY", None)
        env.pop("DISPLAY", None)
        env.pop("DBUS_SESSION_BUS_ADDRESS", None)
        bus = subprocess.Popen(["dbus-daemon", "--session", "--nofork", "--print-address=1"], env=env,
            stdout=subprocess.PIPE, text=True, start_new_session=True)
        env["DBUS_SESSION_BUS_ADDRESS"] = bus.stdout.readline().strip()
        assert env["DBUS_SESSION_BUS_ADDRESS"].startswith("unix:"), "private D-Bus did not start"
        proc = None
        with (base / "qs.log").open("w") as log:
            try:
                def ipc(method="state"):
                    assert proc is not None and proc.poll() is None, "notification fixture exited"
                    result = subprocess.run([quickshell, "ipc", "--pid", str(proc.pid), "call", "harness", method],
                        capture_output=True, text=True, timeout=4, env=env)
                    if result.returncode != 0:
                        return None
                    return json.loads(result.stdout) if method == "state" else True

                def start():
                    nonlocal proc
                    proc = subprocess.Popen([quickshell, "-p", str(shell / "shell.qml"), "--no-color"], env=env,
                        stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                    wait_for(lambda: (s := ipc()) and s["loaded"] and s["historyReady"]
                             and s["dndReady"] and s["statusReady"] and not s["writing"], "QML history and DND ready")

                def snapshot():
                    return json.loads(history.read_text()) if history.exists() else []

                def notify(summary):
                    subprocess.run(["notify-send", "-a", "Prueba", "-t", "0", summary, "cuerpo"],
                        env=env, check=True, timeout=4, capture_output=True)

                def cli(*args):
                    return subprocess.run([str(native), *args], env=env, check=True, timeout=4,
                        capture_output=True, text=True).stdout

                def expect_live(expected):
                    expected = sorted(expected)
                    wait_for(lambda: (s := ipc()) and sorted(s["live"]) == expected, f"live == {expected}")
                    wait_for(lambda: (s := ipc()) and sorted(s["facadeSummaries"]) == expected
                        and s["facadeCount"] == len(expected) and s["historyReady"] and not s["writing"]
                        and not s["clearPending"] and sorted(entry["summary"] for entry in snapshot()) == expected,
                        f"facade == {expected}")
                    assert sorted(entry["summary"] for entry in snapshot()) == expected
                    assert ipc()["writeError"] == "", ipc()

                def hold_next_merge():
                    wait_for(lambda: (s := ipc()) and not s["writing"], "idle writer")
                    (base / "merge-entered").unlink(missing_ok=True)
                    (base / "hold-next-merge").touch()

                def held_request():
                    return wait_for(lambda: json.loads((base / "merge-entered").read_text()), "merge at native barrier")

                start()
                assert json.loads(status.read_text())["dnd"] is False
                notify("Uno")
                notify("Dos")
                expect_live(["Uno", "Dos"])
                first = next(entry for entry in snapshot() if entry["summary"] == "Uno")
                assert {"id", "summary", "body", "appName", "time"} <= first.keys()

                # Delay a real merge while CLI dismisses a saved item and a new
                # notification arrives after the frozen request was sent.
                hold_next_merge()
                notify("Tres")
                request = held_request()
                assert {entry["summary"] for entry in request["entries"]} == {"Uno", "Dos", "Tres"}
                assert request["clear_revision"] == 0
                cli("dismiss", first["id"])
                notify("Cuatro")
                (base / "release-merge").touch()
                expect_live(["Dos", "Tres", "Cuatro"])

                stop(proc)
                start()
                expect_live(["Dos", "Tres", "Cuatro"])

                # A previously completed clear is not replayed when the new
                # notification's merge reads back the old empty array.
                assert ipc("clear") is True
                expect_live([])
                notify("Despues")
                expect_live(["Despues"])
                hold_next_merge()
                notify("Pendiente")
                request = held_request()
                assert any(entry["summary"] == "Pendiente" for entry in request["entries"])
                cli("clear")
                wait_for(lambda: (s := ipc()) and s["live"] == []
                    and s["clearRevision"] > request["clear_revision"], "explicit clear revision reached QML")
                # This arrives after clear was observed, but before the old
                # request returns. Its ID cannot be dismissed by that reply.
                notify("Nueva")
                (base / "release-merge").touch()
                expect_live(["Nueva"])

                # Missing DND storage cannot turn a confirmed enabled value
                # into false, and no popup appears while status is unavailable.
                cli("dnd", "on")
                wait_for(lambda: (s := ipc()) and s["dnd"] and s["facadeDnd"], "DND enabled readback")
                held_status = status.with_suffix(".held")
                status.rename(held_status)
                wait_for(lambda: (s := ipc()) and not s["dndReady"] and not s["statusReady"], "missing DND detected")
                assert ipc()["dnd"] is True and ipc()["facadeDnd"] is True
                notify("Silencio")
                wait_for(lambda: (s := ipc()) and "Silencio" in s["live"], "notification accepted while DND missing")
                assert "Silencio" not in ipc()["popups"]
                held_status.rename(status)
                wait_for(lambda: (s := ipc()) and s["dndReady"] and s["statusReady"], "DND storage recovered")
                assert ipc("toggleDnd") is True
                wait_for(lambda: (s := ipc()) and not s["dnd"] and not s["facadeDnd"], "facade DND toggle confirmed")
                expect_live(["Nueva", "Silencio"])
                log.flush()
                output = (base / "qs.log").read_text()
                assert "ReferenceError" not in output and "TypeError" not in output, output
            except Exception:
                log.flush()
                print((base / "qs.log").read_text()[-6000:])
                raise
            finally:
                stop(proc)
                stop(bus)
    print("PASS: native notification QML readback, concurrent dismissal/clear, later arrivals, restart and DND recovery")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
