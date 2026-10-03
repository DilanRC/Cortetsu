#!/usr/bin/env python3
"""Runtime check of keyboard lock and layout state in the real CortetsuHypr adapter.

`hyprctl` is a stand-in on PATH that replays a fixture, so the check does not
depend on the live keyboard and never changes compositor state.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

SHELL = """import QtQuick
import Quickshell
import "modules"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    // Singletons load on first use; the shell references this one at startup.
    readonly property var adapter: CortetsuHypr
    function verify(value, reason) { if (!value) { console.log("KEYBOARD_FAIL", reason); return; } checks++; }

    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.verify(CortetsuHypr.keyboardKnown, "the startup read is accepted");
                root.verify(CortetsuHypr.capsLock && !CortetsuHypr.numLock, "lock keys come from the main keyboard");
                root.verify(CortetsuHypr.kbLayout === "us" && CortetsuHypr.kbLayoutFull === "English (US)",
                            "the active layout follows active_layout_index");
                root.verify(CortetsuHypr.keyboardWatchers === 0, "nothing polls without a watcher");
                CortetsuHypr.acceptKeyboardState("not json");
                root.verify(!CortetsuHypr.keyboardKnown, "an unreadable answer is reported as unknown");
                CortetsuHypr.acceptKeyboardState(JSON.stringify({ keyboards: [] }));
                root.verify(!CortetsuHypr.keyboardKnown, "no keyboard is reported as unknown");
                CortetsuHypr.watchKeyboard();
            } else if (root.step === 4) {
                root.verify(CortetsuHypr.keyboardKnown && CortetsuHypr.capsLock, "a watcher restores the state by polling");
                CortetsuHypr.unwatchKeyboard();
                root.verify(CortetsuHypr.keyboardWatchers === 0, "releasing the watch stops the poll");
                console.log("KEYBOARD_RUNTIME_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""

DEVICES = {"keyboards": [
    {"name": "virtual", "layout": "es", "active_layout_index": 0, "active_keymap": "Spanish",
     "capsLock": False, "numLock": True, "main": False},
    {"name": "main", "layout": "latam,us", "active_layout_index": 1, "active_keymap": "English (US)",
     "capsLock": True, "numLock": False, "main": True},
]}

with tempfile.TemporaryDirectory(prefix="cortetsu-keyboard-state-") as temporary:
    folder = Path(temporary)
    (folder / "modules").mkdir()
    (folder / "bin").mkdir()
    shutil.copy(ROOT / "modules/CortetsuHypr.qml", folder / "modules/CortetsuHypr.qml")
    fake = folder / "bin/hyprctl"
    fake.write_text("#!/bin/sh\ncat <<'JSON'\n" + json.dumps(DEVICES) + "\nJSON\n")
    fake.chmod(0o700)
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "PATH": f"{folder / 'bin'}:{os.environ['PATH']}"},
        capture_output=True, text=True, timeout=20,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "KEYBOARD_FAIL" not in output, output
    assert "KEYBOARD_RUNTIME_PASS 8" in output, output
    for marker in ("TypeError", "ReferenceError"):
        assert marker not in output, output

print("PASS: keyboard lock and layout state come from the compositor, and unknown stays unknown")
