#!/usr/bin/env python3
"""Runtime check of the session menu against the real session/Content.qml.

The Hyprland adapter, preferences and lock controller are stand-ins that record
what the menu asks for, so nothing is locked, suspended or logged out.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

HYPR = """pragma Singleton
import QtQuick
QtObject {
    property bool usingLua: true
    property var dispatched: []
    function dispatch(request: string): void { dispatched = dispatched.concat([request]); }
}
"""

CONFIG = """pragma Singleton
import QtQuick
QtObject { property bool transparencyEnabled: false }
"""

SHELL = """import QtQuick
import Quickshell
import "modules"
import "modules/session" as Session

ShellRoot {
    id: root
    property int checks: 0
    function verify(value, reason) { if (!value) { console.log("SESSION_FAIL", reason); return; } checks++; }

    QtObject { id: state; property bool session: true }
    QtObject {
        id: lock
        property int requests: 0
        property bool lockReady: false
        property QtObject lock: QtObject { property bool locked: false }
        function requestLock(): void { requests++; }
    }

    Session.Content { id: locked; width: 400; screenState: state; lockController: lock }
    Session.Content { id: unlocked; width: 400; screenState: state }

    function action(id) { return locked.actions.find(item => item.id === id); }

    // Quit is only honoured once the configuration has finished loading.
    Timer { interval: 50; running: true; onTriggered: root.exercise() }

    function exercise() {
        locked.run(action("lock"));
        verify(lock.requests === 1, "lock asks the shell lock controller");
        verify(CortetsuHypr.dispatched.length === 0, "lock does not go through the compositor");
        verify(!state.session, "lock closes the menu");

        state.session = true;
        unlocked.run(action("lock"));
        verify(state.session, "a lock that cannot run keeps the menu open");
        verify(unlocked.failedAction === "lock", "a lock that cannot run is reported");

        locked.run(action("logout"));
        verify(CortetsuHypr.dispatched.length === 0, "logout needs a second activation");
        verify(locked.pendingAction === "logout", "logout is armed after the first activation");
        locked.run(action("logout"));
        verify(CortetsuHypr.dispatched.length === 1 && CortetsuHypr.dispatched[0] === "hl.dsp.exit()",
               "logout uses the Lua dispatcher");
        verify(!state.session, "logout closes the menu");

        console.log("SESSION_RUNTIME_PASS", checks);
        Qt.quit();
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-session-test-") as temporary:
    folder = Path(temporary)
    shutil.copytree(ROOT / "components", folder / "components")
    (folder / "modules/session").mkdir(parents=True)
    for name in ("CortetsuDesign.js", "CortetsuTypography.js"):
        shutil.copy(ROOT / "modules" / name, folder / "modules" / name)
    shutil.copy(ROOT / "modules/session/Content.qml", folder / "modules/session/Content.qml")
    (folder / "modules/CortetsuHypr.qml").write_text(HYPR)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen"},
        capture_output=True, text=True, timeout=20,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "SESSION_FAIL" not in output, output
    assert "SESSION_RUNTIME_PASS 9" in output, output
    for marker in ("TypeError", "ReferenceError", " ERROR"):
        assert marker not in output, output

print("PASS: session lock uses the shell lock, logout uses the Lua dispatcher, failures stay visible")
