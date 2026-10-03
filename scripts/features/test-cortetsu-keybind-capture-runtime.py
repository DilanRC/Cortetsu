#!/usr/bin/env python3
"""Runtime check of the shortcut capture state in the real KeybindsPage.

The helper under HOME is a stand-in that records its arguments and answers
with a conflict or success, so no Hyprland binding is read or written.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

CONFIG = """pragma Singleton
import QtQuick
QtObject { property bool transparencyEnabled: false }
"""

HELPER = """#!/bin/sh
echo "$@" >> "$HOME/calls"
case "$1" in
  list) echo '{"bindings":[{"id":"shell.settings","label":"Ajustes","chord":"SUPER + I","description":"Abrir ajustes"}]}' ;;
  set) if [ "$3" = "SHIFT + SUPER + K" ]; then echo '{"ok":false,"error":"SHIFT + SUPER + K is already assigned to Lanzador"}';
       else echo "{\\"ok\\":true,\\"chord\\":\\"$3\\"}"; fi ;;
esac
"""

SHELL = """import QtQuick
import Quickshell
import "modules/hardware"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    function verify(value, reason) { if (!value) { console.log("CAPTURE_FAIL", reason); return; } checks++; }

    KeybindsPage { id: page; width: 900; height: 600 }

    Timer {
        interval: 350; repeat: true; running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.verify(page.bindings.length === 1 && !page.capturing, "the list loads and nothing is listening");
                page.beginCapture("shell.settings", false, "Ajustes", "SUPER + I");
                root.verify(page.capturing && page.captureRemaining === 1, "capture starts in the listening state");
                page.captureKey(Qt.Key_Meta, Qt.MetaModifier);
                root.verify(page.capturing && page.heldModifiers.join() === "SUPER", "held modifiers are echoed");
                page.captureKey(Qt.Key_A, Qt.NoModifier);
                root.verify(page.capturing && page.captureFailed, "a bare key is refused and keeps listening");
                page.captureKey(Qt.Key_Exclam, Qt.ShiftModifier);
                root.verify(page.capturing && page.captureFailed, "an unsupported key is reported, not dropped");
                page.captureKey(Qt.Key_K, Qt.MetaModifier | Qt.ShiftModifier);
                root.verify(page.busy && page.capturing, "a chord is sent while the overlay stays up");
            } else if (root.step === 2) {
                root.verify(page.capturing && page.captureFailed && page.statusFailed, "a conflict keeps the editor listening");
                root.verify(page.captureMessage.indexOf("already assigned") >= 0, "the conflict names the other action");
                page.captureKey(Qt.Key_F9, Qt.NoModifier);
            } else if (root.step === 3) {
                root.verify(!page.capturing && !page.statusFailed, "a saved chord ends the capture");
                page.beginCapture("shell.settings", false, "Ajustes", "F9");
                page.captureKey(Qt.Key_Escape, Qt.NoModifier);
                root.verify(!page.capturing, "Escape cancels");
                page.beginCapture("shell.settings", false, "Ajustes", "F9");
            } else if (root.step === 6) {
                root.verify(!page.capturing, "the capture ends by itself when the time runs out");
                console.log("CAPTURE_RUNTIME_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-keybind-capture-") as temporary:
    folder = Path(temporary)
    home = folder / "home"
    (home / ".local/bin").mkdir(parents=True)
    helper = home / ".local/bin/cortetsu-keybinds"
    helper.write_text(HELPER)
    helper.chmod(0o700)
    for name in ("components", "theme"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "modules/hardware").mkdir(parents=True)
    for name in ("CortetsuText.qml", "CortetsuIcon.qml", "CortetsuStateLayer.qml", "CortetsuSurface.qml",
                 "CortetsuTypography.js"):
        shutil.copy(ROOT / "modules" / name, folder / "modules" / name)
    for name in ("KeybindsPage.qml", "KeyCaptureOverlay.qml", "KeyCapture.js"):
        shutil.copy(ROOT / "modules/hardware" / name, folder / "modules/hardware" / name)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    page = folder / "modules/hardware/KeybindsPage.qml"
    # Shorten the timeout so the test covers it without waiting ten seconds.
    page.write_text(page.read_text().replace("captureTimeoutMs: 10000", "captureTimeoutMs: 600"))
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home)},
                            capture_output=True, text=True, timeout=30)
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "CAPTURE_FAIL" not in output, output
    assert "CAPTURE_RUNTIME_PASS 11" in output, output
    for marker in ("TypeError", "ReferenceError"):
        assert marker not in output, output
    calls = (home / "calls").read_text().splitlines()
    assert "set shell.settings SHIFT + SUPER + K" in calls and "set shell.settings F9" in calls, calls
    assert not any(call.startswith("set shell.settings A") for call in calls), calls

print("PASS: shortcut capture has one explicit listening state with echo, refusal, conflict, cancel and timeout")
