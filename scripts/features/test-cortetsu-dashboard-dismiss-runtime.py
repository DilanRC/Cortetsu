#!/usr/bin/env python3
"""How the real dashboard layer closes, on the offscreen platform.

DashboardHost maps a full-screen layer only while the dashboard is open, so a
hover open moves the pointer from the drawers window onto that layer. The
drawers window must not close it then (that looped open/close); the layer
closes it instead:

- hover open: stays while the pointer travels to the panel, closes when the
  pointer leaves the panel after reaching it;
- shortcut open: leaving the panel does not close it;
- a click outside closes it, a click on an empty part of the panel does not;
- Escape closes it;
- on a narrow screen with no weather and no player it fits and says so,
  without filler text or "--" readings.

Set CORTETSU_RENDER_DIR to keep a PNG of that narrow dashboard.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

SHELL = """import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "modules/dashboard"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property bool busy: false
    property bool grabbed: false
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("DASH_FAIL", reason); else checks++; }

    QtObject {
        id: state
        property bool dashboard: false
        property string dashboardOpenedBy: ""
        property int dashboardTab: 0
        property date dashboardDate: new Date(2026, 9, 28, 12, 0)
    }

    TestEvent { id: events }

    Window {
        id: window
        width: 1600; height: 1000; visible: true; color: CortetsuDesign.colorSumi
        DashboardLayer { id: layer; anchors.fill: parent; open: state.dashboard; screenState: state }
    }

    function move(x, y) { events.mouseMove(layer, x, y, -1, Qt.NoButton, Qt.NoModifier); }
    function click(x, y) { events.mouseClick(layer, x, y, Qt.LeftButton, Qt.NoModifier, -1); }
    // A point on the panel's own background: its top-left padding.
    function onPanel() { return layer.panel.mapToItem(layer, 6, 6); }

    readonly property var steps: [
        () => window.active,
        // Hover open: the pointer is at the top edge, outside the panel.
        () => { state.dashboardOpenedBy = "hover"; state.dashboard = true; move(800, 2); return true; },
        () => { verify(state.dashboard, "a hover open stays while the pointer travels to the panel");
                const p = onPanel(); move(p.x, p.y); return true; },
        () => { verify(layer.pointerOnPanel, "the pointer is on the panel");
                move(4, 990); return true; },
        () => { verify(!state.dashboard, "leaving the panel after reaching it closes a hover open"); return true; },
        // Shortcut open.
        () => { state.dashboardOpenedBy = ""; state.dashboard = true; const p = onPanel(); move(p.x, p.y); return true; },
        () => { move(4, 990); return true; },
        () => { verify(state.dashboard, "leaving the panel does not close a shortcut open");
                const p = onPanel(); click(p.x, p.y); return true; },
        () => { verify(state.dashboard, "a click on an empty part of the panel keeps it open");
                click(4, 990); return true; },
        () => { verify(!state.dashboard, "a click outside the panel closes it");
                state.dashboard = true; return true; },
        () => layer.activeFocus,
        () => { events.keyClick(Qt.Key_Escape, Qt.NoModifier, -1); return true; },
        () => { verify(!state.dashboard, "Escape closes it");
                // Narrow screen, no weather and no player: honest empty states.
                window.width = 1000; window.height = 640; state.dashboard = true; return true; },
        () => {
            verify(layer.panel.width <= 1000 - CortetsuDesign.spacingSection * 2, `the panel fits a narrow screen: ${layer.panel.width}`);
            const shown = [];
            (function walk(item) {
                if (!item.visible) return;
                if (typeof item.text === "string" && item.text.length > 0) shown.push(item.text);
                for (const kid of item.children ?? []) walk(kid);
            })(layer.panel);
            verify(shown.includes("Tiempo no disponible"), "no weather reading says so");
            verify(shown.includes("Nada en reproducción"), "no player says so");
            const filler = shown.filter(text => /^--$|Your desktop|Ambient|shell is ready|NOW|Live context|Desktop context/.test(text));
            verify(filler.length === 0, `no filler or placeholder data: ${filler}`);
            if (root.renderDir) layer.grabToImage(r => { r.saveToFile(`${root.renderDir}/dashboard-narrow.png`); root.grabbed = true; });
            else root.grabbed = true;
            return true; },
        () => root.grabbed
    ]

    Timer {
        interval: 120; repeat: true; running: true
        onTriggered: {
            if (root.busy) return;
            if (root.step >= root.steps.length) { console.log(`DASH_RUNTIME_PASS ${root.checks}`); Qt.quit(); return; }
            root.busy = true;
            try { if (root.steps[root.step]()) root.step++; }
            catch (error) { console.log("DASH_FAIL step", root.step, error); Qt.quit(); }
            root.busy = false;
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("DASH_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

WEATHER = """pragma Singleton
import QtQml
import Quickshell

Singleton {
    property string city: ""
    property var cc: null
    readonly property string icon: ""
    readonly property string temp: ""
    readonly property string feelsLike: ""
    readonly property string description: ""
    function reload() {}
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-dashboard-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    shutil.copy(ROOT / "base/services/VPN.qml", folder / "services/VPN.qml")
    # No network in the test: the weather service never gets a reading.
    (folder / "services/Weather.qml").write_text(WEATHER)
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config").mkdir(parents=True)
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_STATE_HOME": str(home / ".local/state"),
           "CORTETSU_RENDER_DIR": os.environ.get("CORTETSU_RENDER_DIR", "")}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert "DASH_RUNTIME_PASS 11" in output, output
    for marker in ("DASH_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type"):
        assert marker not in output, output

print("PASS: the dashboard closes on leaving after a hover open, on a click outside and on Escape, "
      "and stays for a shortcut open and a click inside")
