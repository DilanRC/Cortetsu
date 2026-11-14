#!/usr/bin/env python3
"""A Hub button's focus mark follows the keyboard, not the pointer (offscreen).

HubButton takes the keyboard focus on a press, and the Hub keeps the
keyboard after a click (OnDemand). On the live session that left the focus
ring and the focus tooltip (the network one, with the SSID and its signal)
over the Hub, the pointer long gone, until another window took the keyboard.
Focus that a press gave shows no mark; the first key, or focus that arrives
by keyboard, shows it. qmltestrunner cannot load HubButton (it pulls in
Quickshell through the Evolving Mark), so this runs Quickshell offscreen.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
CHECKS = 13

SHELL = """import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "modules"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    function verify(value, reason) { if (!value) console.log("HUBBUTTON_FAIL", reason); else checks++; }
    function find(item, test) {
        if (test(item)) return item;
        for (const kid of [...(item.children ?? []), ...(item.resources ?? [])]) { const hit = find(kid, test); if (hit) return hit; }
        return null;
    }
    function surfaceOf(button) { return find(button, c => c !== button && "outlined" in c && "hoverColor" in c && "focused" in c); }
    function tooltipOf(button) { return find(button, c => "wanted" in c && "placement" in c); }

    TestEvent { id: events }

    Window {
        id: window
        width: 400; height: 200; visible: true
        // The status island around it: its "focus inside" mark follows the same rule.
        Item {
            id: statusSegment
            property bool engaged: false
            x: 110; y: 90; width: 70; height: 70
            CortetsuIsland { id: island }
            HubButton { id: network; x: 10; y: 10; icon: "wifi"; tooltip: "Red · señal 57 %"; tooltipOnHover: false }
        }
        HubButton { id: battery; x: 220; y: 100; icon: "battery_full"; tooltip: "Batería"; tooltipOnHover: false }
        Component.onCompleted: requestActivate()
    }

    readonly property var steps: [
        () => window.active,
        () => { events.mousePress(network, 24, 24, Qt.LeftButton, Qt.NoModifier, -1);
                events.mouseRelease(network, 24, 24, Qt.LeftButton, Qt.NoModifier, -1);
                events.mouseMove(window.contentItem, 10, 10, -1, Qt.NoButton, Qt.NoModifier);
                return true; },
        () => { verify(network.activeFocus, "a press gives the button the keyboard");
                verify(!surfaceOf(network).focused, "no focus ring for a focus the pointer gave");
                verify(!tooltipOf(network).wanted, "no focus tooltip left behind by the pointer");
                verify(!island.focused, "nor a focus-inside mark on its island");
                return true; },
        () => { events.keyClick(Qt.Key_Shift, Qt.NoModifier, -1); return true; },
        () => { verify(network.activeFocus, "a key keeps the focus where it is");
                verify(surfaceOf(network).focused, "a key shows where the keyboard is");
                verify(tooltipOf(network).wanted, "and the focus tooltip");
                verify(island.focused, "and its island's focus-inside mark");
                return true; },
        () => { battery.forceActiveFocus(Qt.TabFocusReason); return true; },
        () => { verify(surfaceOf(battery).focused, "focus that arrives by keyboard shows at once");
                verify(!surfaceOf(network).focused, "the previous button lets its mark go");
                return true; },
        () => { events.mouseClick(network, 24, 24, Qt.LeftButton, Qt.NoModifier, -1);
                events.mouseMove(window.contentItem, 10, 10, -1, Qt.NoButton, Qt.NoModifier);
                return true; },
        () => { verify(!surfaceOf(network).focused, "a new press hides the mark again");
                events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
                return true; },
        () => { verify(surfaceOf(network).focused, "Enter is keyboard use and shows the mark");
                verify(!tooltipOf(battery).wanted, "the other button keeps no tooltip");
                return true; }
    ]

    Timer {
        interval: 60; repeat: true; running: true
        property bool busy: false
        onTriggered: {
            if (busy) return;
            busy = true;
            if (root.step >= root.steps.length) { console.log(`HUBBUTTON_PASS ${root.checks}`); Qt.quit(); return; }
            if (root.steps[root.step]()) root.step++;
            busy = false;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.log("HUBBUTTON_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-hubbutton-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    shutil.copy(ROOT / "base/services/VPN.qml", folder / "services/VPN.qml")
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config").mkdir(parents=True)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_STATE_HOME": str(home / ".local/state")}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert f"HUBBUTTON_PASS {CHECKS}" in output, output[-4000:]
    for marker in ("HUBBUTTON_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type", "Unable to assign"):
        assert marker not in output, output[-4000:]

print(f"PASS: a Hub button shows its focus mark for the keyboard, not for a press ({CHECKS} checks)")
