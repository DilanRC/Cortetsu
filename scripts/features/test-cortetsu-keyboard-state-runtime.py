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
import Quickshell.Io
import "modules"
import "services"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    // Singletons load on first use; the shell references this one at startup.
    readonly property var adapter: CortetsuHypr
    function verify(value, reason) { if (!value) { console.log("KEYBOARD_FAIL", reason); return; } checks++; }

    Process {
        id: enableChangedDevice
        command: ["touch", Quickshell.env("CORTETSU_TEST_TRIGGER_FILE")]
    }

    Timer {
        interval: 500; repeat: true; running: true
        onTriggered: {
            if (!CortetsuConfig.loaded)
                return;
            root.step++;
            if (root.step === 1) {
                root.verify(CortetsuHypr.keyboardKnown, "the startup read is accepted");
                root.verify(CortetsuHypr.capsLock && !CortetsuHypr.numLock, "lock keys come from the main keyboard");
                root.verify(CortetsuHypr.kbLayout === "us" && CortetsuHypr.kbLayoutFull === "English (US)",
                            "the active layout follows active_layout_index");
                root.verify(CortetsuHypr.keyboardWatchers === 0, "there is no explicit keyboard-state consumer");
                CortetsuConfig.load(JSON.stringify({ bar: { persistent: true,
                    scrollActions: { brightness: false, workspaces: false },
                    tray: { compact: true }, activeWindow: { compact: false },
                    clock: { showDate: true } } }));
                root.verify(!("persistent" in CortetsuConfig.bar)
                    && !("workspaces" in CortetsuConfig.bar.scrollActions)
                    && !("brightness" in CortetsuConfig.bar.scrollActions)
                    && !("compact" in CortetsuConfig.bar.tray)
                    && !("compact" in CortetsuConfig.bar.activeWindow)
                    && !("showDate" in CortetsuConfig.bar.clock),
                    "old retired bar preferences load and remain unexposed");
                CortetsuHypr.acceptKeyboardState("not json");
                root.verify(!CortetsuHypr.keyboardKnown, "an unreadable answer is reported as unknown");
                CortetsuHypr.acceptKeyboardState(JSON.stringify({ keyboards: [] }));
                root.verify(!CortetsuHypr.keyboardKnown, "no keyboard is reported as unknown");
                CortetsuConfig.toastCapsLockChanged = true;
                CortetsuConfig.toastNumLockChanged = true;
                CortetsuConfig.toastKbLayoutChanged = true;
                CortetsuHypr.acceptKeyboardState(JSON.stringify(@DEVICES@));
                CortetsuHypr.acceptKeyboardState(JSON.stringify(@DEVICES@));
                CortetsuHypr.acceptKeyboardState(JSON.stringify(@CHANGED_DEVICES@));
                root.verify(CortetsuToaster.toasts.length === 3, "lock and layout changes create three toasts " + JSON.stringify(CortetsuToaster.toasts.map(t => t.title + ":" + t.message)));
                enableChangedDevice.running = true;
                CortetsuHypr.watchKeyboard();
            } else if (root.step === 4) {
                root.verify(CortetsuHypr.keyboardKnown && !CortetsuHypr.capsLock
                    && CortetsuHypr.numLock && CortetsuHypr.kbLayoutFull === "Spanish",
                    "the keyboard poll accepts changed lock and layout state");
                root.verify(CortetsuToaster.toasts.length === 3, "lock and layout changes create three toasts " + JSON.stringify(CortetsuToaster.toasts.map(t => t.title + ":" + t.message)));
                CortetsuHypr.unwatchKeyboard();
                root.verify(CortetsuHypr.keyboardWatchers === 0, "releasing the explicit watch is balanced");
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
CHANGED_DEVICES = {"keyboards": [
    {"name": "main", "layout": "es,us", "active_layout_index": 0, "active_keymap": "Spanish",
     "capsLock": False, "numLock": True, "main": True},
]}

with tempfile.TemporaryDirectory(prefix="cortetsu-keyboard-state-") as temporary:
    folder = Path(temporary)
    (folder / "modules").mkdir()
    (folder / "bin").mkdir()
    (folder / "config/cortetsu").mkdir(parents=True)
    (folder / "config/cortetsu/preferences.json").write_text(json.dumps({
        "toastCapsLockChanged": False,
        "toastNumLockChanged": False,
        "toastKbLayoutChanged": False,
    }))
    shutil.copy(ROOT / "modules/CortetsuHypr.qml", folder / "modules/CortetsuHypr.qml")
    shutil.copy(ROOT / "modules/CortetsuToplevels.js", folder / "modules/CortetsuToplevels.js")
    shutil.copy(ROOT / "modules/CortetsuConfig.qml", folder / "modules/CortetsuConfig.qml")
    (folder / "services").mkdir()
    shutil.copy(ROOT / "services/CortetsuToaster.qml", folder / "services/CortetsuToaster.qml")
    fake = folder / "bin/hyprctl"
    fake.write_text("""#!/bin/sh
echo "$*" >> "$CORTETSU_TEST_TRIGGER_FILE.calls"
if [ ! -f "$CORTETSU_TEST_TRIGGER_FILE" ]; then
    cat <<'JSON'
""" + json.dumps(DEVICES) + """
JSON
else
    cat <<'JSON'
""" + json.dumps(CHANGED_DEVICES) + """
JSON
fi
""")
    fake.chmod(0o700)
    shell = SHELL.replace("@DEVICES@", json.dumps(DEVICES)).replace("@CHANGED_DEVICES@", json.dumps(CHANGED_DEVICES))
    (folder / "shell.qml").write_text(shell)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "PATH": f"{folder / 'bin'}:{os.environ['PATH']}",
             "XDG_CONFIG_HOME": str(folder / "config"), "CORTETSU_TEST_TRIGGER_FILE": str(folder / "changed-device"),
             "CORTETSU_SYSFS_ROOT": str(folder / "no-sysfs")},
        capture_output=True, text=True, timeout=20,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "KEYBOARD_FAIL" not in output, output
    assert "KEYBOARD_RUNTIME_PASS 11" in output, output
    for marker in ("TypeError", "ReferenceError"):
        assert marker not in output, output

    # With lock-key toasts on and no keyboard watcher, hyprctl runs once at startup
    # and once when a LED changes: LEDs are read in-process, layouts come as events.
    # Outside the shell folder: Quickshell reloads when files inside it change.
    outside = Path(tempfile.mkdtemp(prefix="cortetsu-keyboard-calls-"))
    (outside / "config/cortetsu").mkdir(parents=True)
    (outside / "config/cortetsu/preferences.json").write_text(json.dumps({
        "toastCapsLockChanged": True, "toastNumLockChanged": True, "toastKbLayoutChanged": True}))
    calls = outside / "idle.calls"
    leds = outside / "sys/class/leds"
    for name, value in (("input9::capslock", "1"), ("input9::numlock", "0")):
        (leds / name).mkdir(parents=True)
        (leds / name / "brightness").write_text(value + "\n")
    (folder / "idle.qml").write_text('import QtQuick\nimport Quickshell\nimport "modules"\n'
        'ShellRoot { readonly property var a: CortetsuHypr\n'
        '  Timer { interval: 3500; running: true; onTriggered: Qt.quit() } }\n')
    # Caps Lock LED turns off halfway: exactly one extra hyprctl, not one per second.
    flip = subprocess.Popen(["sh", "-c", f"sleep 2; echo 0 > '{leds}/input9::capslock/brightness'"])
    # Detached from any running compositor, so no live Hyprland event refreshes it.
    isolated = {k: v for k, v in os.environ.items() if k not in ("WAYLAND_DISPLAY", "HYPRLAND_INSTANCE_SIGNATURE")}
    idle = subprocess.run(["quickshell", "-p", str(folder / "idle.qml")],
        env={**isolated, "QT_QPA_PLATFORM": "offscreen", "PATH": f"{folder / 'bin'}:{os.environ['PATH']}",
             "XDG_CONFIG_HOME": str(outside / "config"), "CORTETSU_TEST_TRIGGER_FILE": str(outside / "idle"),
             "CORTETSU_SYSFS_ROOT": str(outside / "sys")},
        capture_output=True, text=True, timeout=20)
    assert idle.returncode == 0 and "Configuration Loaded" in idle.stdout + idle.stderr, idle.stdout + idle.stderr
    assert "TypeError" not in idle.stderr and "ReferenceError" not in idle.stderr, idle.stderr
    flip.wait()
    assert calls.read_text().count("devices") == 2, calls.read_text() + idle.stdout + idle.stderr
    shutil.rmtree(outside)

print("PASS: keyboard lock and layout state come from the compositor, and unknown stays unknown")
