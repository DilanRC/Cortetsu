#!/usr/bin/env python3
"""The real ScreenSharePanel on the offscreen platform, in a temporary tree.

A stub controller records what the panel asks for. Keyboard: 1 shares the
first screen at once, Tab moves to Ventanas, Alt+R turns on "Recordar", Enter
shares the selected window with the remember flag, Tab again reaches Región.
An empty window list shows its empty state and disables Compartir.

Set CORTETSU_RENDER_DIR to keep PNGs of each tab.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")

SHELL = """import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "modules/screenshare" as Share
import "components/containers"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("SHARE_FAIL", reason); else checks++; }
    function grab(name) { if (renderDir) panel.grabToImage(r => r.saveToFile(`${renderDir}/share-${name}.png`)); }

    QtObject {
        id: controller
        property bool choosing: true
        property var windows: [
            { handle: 7, class: "kitty", title: "notas — un título de ventana muy largo que no cabe en la tarjeta", address: "0" },
            { handle: 9, class: "firefox", title: "Docs", address: "0" }
        ]
        property var calls: []
        function shareScreen(output, remember) { calls = calls.concat([["screen", output, remember]]); }
        function shareWindow(handle, remember) { calls = calls.concat([["window", handle, remember]]); }
        function pickRegion(remember) { calls = calls.concat([["region", remember]]); }
    }

    Window {
        id: window
        width: 1600; height: 1000; visible: true; color: "#0B0D10"
        // As in ScreenSharePicker: the host, not the panel, centres it.
        CortetsuPopupHost {
            open: true; animate: false
            Share.ScreenSharePanel { id: panel; controller: controller; maxWidth: 900; maxHeight: 640 }
        }
    }
    TestEvent { id: events }
    function key(k, mods) { events.keyClick(k, mods ?? Qt.NoModifier, panel); }

    readonly property var steps: [
        () => { panel.forceActiveFocus(); return panel.activeFocus && panel.width > 0; },
        () => { const c = panel.mapToItem(null, panel.width / 2, panel.height / 2);
                verify(Math.abs(c.x - window.width / 2) < 2 && Math.abs(c.y - window.height / 2) < 2,
                       `the picker opens centred: centre ${c.x},${c.y} on ${window.width}x${window.height}`); return true; },
        () => { grab("screens"); key(Qt.Key_1); return true; },
        () => { verify(controller.calls.length === 1 && controller.calls[0][0] === "screen"
                    && controller.calls[0][2] === false, "1 shares the first screen"); key(Qt.Key_Tab); return true; },
        () => { verify(panel.tab === 1, "Tab reaches Ventanas"); key(Qt.Key_Right); key(Qt.Key_R, Qt.AltModifier); return true; },
        () => { verify(panel.selected === 1 && panel.remember, `arrow and Alt+R tab=${panel.tab} sel=${panel.selected} rem=${panel.remember} count=${panel.count}`); grab("windows"); key(Qt.Key_Return); return true; },
        () => { const c = controller.calls[1]; verify(c && c[0] === "window" && c[1] === 9 && c[2] === true, `Enter shares window 9 remembered: ${JSON.stringify(c)}`);
                key(Qt.Key_Tab); return true; },
        () => { verify(panel.tab === 2, "Tab reaches Región"); grab("region"); key(Qt.Key_Return); return true; },
        () => { verify(controller.calls[2]?.[0] === "region", "Enter on Región picks a region");
                controller.windows = []; key(Qt.Key_Backtab); return true; },
        () => { verify(panel.tab === 1 && panel.count === 0, "empty window list"); grab("empty");
                key(Qt.Key_Return); return true; },
        () => { verify(controller.calls.length === 3, "Enter with nothing to share does nothing"); return true; }
    ]

    Timer {
        interval: 60; repeat: true; running: true
        onTriggered: {
            if (root.step >= root.steps.length) {
                console.log(`SHARE_RUNTIME_PASS ${root.checks}`);
                Qt.quit();
                return;
            }
            if (root.steps[root.step]())
                root.step++;
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.log("SHARE_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-share-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config").mkdir(parents=True)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_STATE_HOME": str(home / ".local/state"), "CORTETSU_RENDER_DIR": RENDER_DIR}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert "SHARE_RUNTIME_PASS 9" in output, output
    for marker in ("SHARE_FAIL", "TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type"):
        assert marker not in output, output

print("PASS: the share picker shares by digit, arrows and Enter, remembers with Alt+R, reaches Región and shows its empty state")
