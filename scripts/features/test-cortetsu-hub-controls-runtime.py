#!/usr/bin/env python3
"""The real BottomHub status segment and its popouts on the offscreen platform.

Checks what qmltestrunner cannot load (these files pull in Quickshell): the
notification badge stays a circle for one digit and grows for "9+", no
status item takes focus by loading, the Wi-Fi password field marks its focus, and the popouts with an icon badge load
without QML errors.

Set CORTETSU_RENDER_DIR to keep a PNG of each piece.
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
import Quickshell
import "modules"
import "modules/bar/popouts" as Pop
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("HUB_FAIL", reason); else checks++; }
    function grab(item, name) { if (renderDir) item.grabToImage(r => r.saveToFile(`${renderDir}/hub-${name}.png`)); }
    function find(item, test) {
        if (test(item)) return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) { const hit = find(kids[i], test); if (hit) return hit; }
        return null;
    }

    QtObject { id: popouts; property string currentName: ""; function close() {} }

    Window {
        width: 1100; height: 900; visible: true; color: CortetsuDesign.colorSumi
        Column {
            x: 16; y: 16; spacing: 16
            CortetsuStatusSegment {
                id: segment
                volumeIcon: "volume_up"; volumeMuted: false
                networkIcon: "wifi"; networkTooltip: ""; networkActive: true
                bluetoothIcon: "bluetooth"; bluetoothActive: false
                batteryIcon: "battery_full"; batteryCritical: false; batteryTooltip: ""
                audioVisible: true; networkVisible: true; bluetoothVisible: true; batteryVisible: true
                statusPopoutsEnabled: true; notificationCount: 0; sidebarActive: false
                recordingActive: true; dndActive: true; idleInhibited: true
                now: new Date(2026, 9, 28, 12, 0); sessionActive: false
            }
            Row {
                spacing: 16
                Pop.CortetsuAudioPopup { id: audio; width: 340; height: implicitHeight; popouts: popouts }
                Pop.CortetsuBatteryPopup { id: battery; width: 340; height: implicitHeight }
                Pop.CortetsuWifiPasswordPopup { id: wifi; width: 340; height: implicitHeight; popouts: popouts }
            }
            Row {
                spacing: 16
                Pop.CortetsuBluetoothPopup { id: bluetooth; width: 340; height: implicitHeight; popouts: popouts }
                Pop.CortetsuNetworkPopup { id: network; width: 340; height: implicitHeight; popouts: popouts }
            }
        }
    }

    readonly property var steps: [
        // Focus only shows once the window is active.
        () => { if (!segment.Window.window?.active) return false;
                segment.notificationCount = 3; return true; },
        () => { const t = find(segment, c => c.text === "3" && c.parent?.radius !== undefined);
                verify(t && t.parent.width === t.parent.height, `one digit keeps a circle: ${t?.parent.width}x${t?.parent.height}`);
                grab(segment, "segment-3"); segment.notificationCount = 12; return true; },
        () => { const t = find(segment, c => c.text === "9+");
                verify(t && t.parent.width >= t.implicitWidth + 4, `9+ fits: badge ${t?.parent.width}, text ${t?.implicitWidth}`);
                verify(!find(segment, c => c.activeFocus === true && c.label !== undefined), "no status item takes focus by loading");
                grab(segment, "segment-9plus"); return true; },
        () => { const field = find(wifi, c => c.echoMode === TextInput.Password);
                verify(field !== null, "password field found");
                field.forceActiveFocus(); return field.activeFocus; },
        () => { const field = find(wifi, c => c.echoMode === TextInput.Password);
                verify(Qt.colorEqual(field.background.border.color, CortetsuDesign.colorIndicator), "focused field shows the indicator edge");
                grab(wifi, "wifi-focused");
                for (const [item, name] of [[audio, "audio"], [battery, "battery"], [bluetooth, "bluetooth"], [network, "network"]]) {
                    verify(item.height > 0, `${name} popout has a size`);
                    grab(item, name);
                }
                return true; },
        () => true
    ]

    Timer {
        interval: 80; repeat: true; running: true
        onTriggered: {
            if (root.step >= root.steps.length) { console.log(`HUB_RUNTIME_PASS ${root.checks}`); Qt.quit(); return; }
            if (root.steps[root.step]()) root.step++;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.log("HUB_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-hub-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    # Connectivity reads the VPN singleton, which only base/ provides.
    shutil.copy(ROOT / "base/services/VPN.qml", folder / "services/VPN.qml")
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
    assert "HUB_RUNTIME_PASS 9" in output, output
    for marker in ("HUB_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type"):
        assert marker not in output, output

print("PASS: the hub badge fits its count, the Wi-Fi field marks focus and the badge popouts load cleanly")
