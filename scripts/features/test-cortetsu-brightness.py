#!/usr/bin/env python3
"""Brightness per screen: keys reach a receiver, each screen drives only its own backlight."""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "cortetsu/services/Brightness.qml"

FAKE_BRIGHTNESSCTL = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
state = Path(os.environ["FAKE_BACKLIGHT_STATE"])
levels = json.loads(state.read_text())
args = sys.argv[1:]
with open(os.environ["FAKE_BACKLIGHT_LOG"], "a") as log:
    log.write(json.dumps(args) + "\n")
if args == ["-l", "-m"]:
    for name, value in levels.items():
        print(f"{name},backlight,{value},{round(value * 100 / 65535)}%,65535")
    print("input2::capslock,leds,0,0%,1")
elif len(args) == 3 and args[0] == "-d" and args[2] == "g":
    if args[1] not in levels: sys.exit(1)
    # Slow enough that key repeat lands while a read-back is in flight.
    time.sleep(0.2)
    print(levels[args[1]])
elif len(args) == 4 and args[0] == "-d" and args[2] == "s":
    if args[1] not in levels: sys.exit(1)
    levels[args[1]] = max(0, min(65535, int(args[3])))
    state.write_text(json.dumps(levels))
else:
    sys.exit(2)
'''

FAKE_FIND = r'''#!/usr/bin/env python3
import os, sys
assert sys.argv[1:] == ["/sys/class/backlight", "-mindepth", "1", "-maxdepth", "1", "-printf", "%f\t%l\n"], sys.argv
print(os.environ["FAKE_BACKLIGHTS"], end="")
'''

STUBS = {
    "qmldir": "singleton CortetsuHypr 1.0 CortetsuHypr.qml\nsingleton CortetsuConfig 1.0 CortetsuConfig.qml\n"
              "singleton ShortcutRegistry 1.0 ShortcutRegistry.qml\nCortetsuShortcut 1.0 CortetsuShortcut.qml\n",
    "CortetsuHypr.qml": """pragma Singleton
import QtQuick
QtObject {
    property string focusedName: "eDP-1"
    function monitorFor(screen) { return { focused: screen?.name === focusedName, id: 0 }; }
}
""",
    "CortetsuConfig.qml": "pragma Singleton\nimport QtQuick\nQtObject { property real brightnessIncrement: 0.1 }\n",
    "ShortcutRegistry.qml": """pragma Singleton
import QtQuick
QtObject {
    property var names: []
    property var byName: ({})
    function add(shortcut) { names = [...names, shortcut.name]; byName[shortcut.name] = shortcut; }
}
""",
    # Stands in for Quickshell's GlobalShortcut: Hyprland calls pressed().
    "CortetsuShortcut.qml": """import QtQuick
QtObject {
    property string name
    property string description
    signal pressed()
    Component.onCompleted: ShortcutRegistry.add(this)
}
""",
}

SHELL = """import QtQuick
import Quickshell
import "services"
import "modules"
ShellRoot {
    id: root
    property int stage: 0
    property int edpReads: 0
    readonly property string expected: Quickshell.env("EXPECT_DEVICE")
    function fail(message) { console.error("BRIGHTNESS_FAIL", message); Qt.quit(); }
    function edp() { return Brightness.getMonitor("eDP-1"); }
    function hdmi() { return Brightness.getMonitor("HDMI-A-1"); }
    function press(name) { ShortcutRegistry.byName[name].pressed(); }
    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            const edp = root.edp(), hdmi = root.hdmi();
            if (root.stage === 0) {
                if (!edp || edp.brightness < 0) return;
                if (ShortcutRegistry.names.filter(n => n === "brightnessUp").length !== 1
                    || ShortcutRegistry.names.filter(n => n === "brightnessDown").length !== 1)
                    return root.fail("receivers " + ShortcutRegistry.names);
                if (edp.device !== root.expected || !edp.supported) return root.fail("eDP device " + edp.device);
                if (!hdmi || hdmi.supported || hdmi.brightness !== -1 || hdmi.device !== "")
                    return root.fail("HDMI must have no backlight");
                if (Math.abs(edp.brightness - 0.5) > 0.001) return root.fail("readback " + edp.brightness);
                root.press("brightnessUp");
                root.stage = 1;
            } else if (root.stage === 1) {
                if (Math.abs(edp.brightness - 0.6) > 0.001) return;
                // Key repeat outruns brightnessctl; the last value must land.
                for (let i = 0; i < 6; i++) root.press("brightnessUp");
                root.stage = 2;
            } else if (root.stage === 2) {
                if (Math.abs(edp.brightness - 1) > 0.001 || edp.writeProcess.running) return;
                CortetsuHypr.focusedName = "HDMI-A-1";
                root.press("brightnessDown");
                root.press("brightnessDown");
                root.stage = 3;
            } else if (root.stage === 3) {
                if (edp.writeProcess.running || Math.abs(edp.brightness - 1) > 0.001)
                    return root.fail("focus on HDMI dimmed the internal panel");
                // Unplug and replug HDMI: stale monitors must not linger.
                root.testScreens = [root.testScreens[0]];
                root.stage = 4;
            } else if (root.stage === 4) {
                if (Brightness.monitors.length !== 1 || root.hdmi() !== null) return root.fail("hotplug kept a monitor");
                root.testScreens = [root.testScreens[0], hdmiScreen];
                root.stage = 5;
            } else if (root.stage === 5) {
                if (Brightness.monitors.length !== 2 || !hdmi || hdmi.supported) return;
                CortetsuHypr.focusedName = "eDP-1";
                root.press("brightnessDown");
                root.stage = 6;
            } else if (root.stage === 6) {
                if (Math.abs(edp.brightness - 0.9) > 0.001 || edp.settling) return;
                root.stage = 7;
            } else if (root.stage < 11) {
                // One press per tick: each lands during a write or a read-back.
                root.press("brightnessDown");
                root.stage += 1;
            } else {
                if (edp.settling || Math.abs(edp.brightness - 0.5) > 0.001) return;
                console.log("BRIGHTNESS_FIXTURE_PASS"); Qt.quit();
            }
        }
    }
    QtObject { id: edpScreen; property string name: "eDP-1" }
    QtObject { id: hdmiScreen; property string name: "HDMI-A-1" }
    property var testScreens: [edpScreen, hdmiScreen]
    // The fixture has no compositor: screens are plain objects.
    Component.onCompleted: Brightness.screens = Qt.binding(() => root.testScreens)
    Timer { interval: 15000; running: true; onTriggered: root.fail("deadline") }
}
"""


def run(case: str, backlights: str, expected: str) -> list[list[str]]:
    with tempfile.TemporaryDirectory(prefix=f"cortetsu-brightness-{case}-") as temporary:
        root = Path(temporary)
        (root / "services").mkdir()
        (root / "modules").mkdir()
        shutil.copy(SOURCE, root / "services/Brightness.qml")
        for name, text in STUBS.items():
            (root / "modules" / name).write_text(text)
        (root / "shell.qml").write_text(SHELL)
        bin_dir = root / "bin"
        bin_dir.mkdir()
        for name, text in (("brightnessctl", FAKE_BRIGHTNESSCTL), ("find", FAKE_FIND)):
            (bin_dir / name).write_text(text)
            (bin_dir / name).chmod(0o755)
        state, log = root / "levels.json", root / "calls.log"
        state.write_text(json.dumps({expected: 32768}))
        log.write_text("")
        env = dict(os.environ, PATH=f"{bin_dir}:{os.environ['PATH']}", QT_QPA_PLATFORM="offscreen",
                   FAKE_BACKLIGHT_STATE=str(state), FAKE_BACKLIGHT_LOG=str(log),
                   FAKE_BACKLIGHTS=backlights, EXPECT_DEVICE=expected)
        env.pop("WAYLAND_DISPLAY", None)
        result = subprocess.run(["quickshell", "-p", str(root / "shell.qml"), "--no-color"], env=env, text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=25)
        assert "BRIGHTNESS_FIXTURE_PASS" in result.stdout and "BRIGHTNESS_FAIL" not in result.stdout, result.stdout
        assert " WARN" not in result.stdout and "TypeError" not in result.stdout, result.stdout
        calls = [json.loads(line) for line in log.read_text().splitlines()]
        writes = [call for call in calls if len(call) == 4 and call[2] == "s"]
        assert writes and all(call[1] == expected for call in writes), f"a write left the panel's device: {calls}"
        assert all(call[1] for call in calls if call[0] == "-d"), "brightnessctl called without a device"
        assert len(writes) <= 10, f"key repeat was not coalesced: {writes}"
        assert json.loads(state.read_text())[expected] == round(0.5 * 65535)
        return calls


# amdgpu registers the backlight under its connector, as on the Victus.
run("connector", "amdgpu_bl2\t../../devices/pci0000:00/0000:00:08.1/0000:06:00.0/drm/card2/card2-eDP-1/amdgpu_bl2\n",
    "amdgpu_bl2")
# A firmware backlight has no connector; only the single internal panel may take it.
run("firmware", "acpi_video0\t../../devices/pci0000:00/0000:00:02.0/backlight/acpi_video0\n", "acpi_video0")
print("PASS: brightness keys have receivers; eDP drives its own backlight, HDMI is unsupported, hotplug is clean")
