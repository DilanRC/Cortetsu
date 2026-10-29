#!/usr/bin/env python3
"""The real notification card and toast on the offscreen platform.

Checks the shared icon badge (indicator tone, vermillion when urgent), that a
long summary or message stays inside its card, and that a closed notification
fades out. These files pull in Quickshell, so qmltestrunner cannot load them.

Set CORTETSU_RENDER_DIR to keep a PNG of each card.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
LONG = "Actualización del sistema " * 12

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "modules/notifications" as N
import "modules/utilities/toasts" as T
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("NOTICE_FAIL", reason); else checks++; }
    function grab(item, name) { if (renderDir) item.grabToImage(r => r.saveToFile(`${renderDir}/notice-${name}.png`)); }
    function find(item, test) {
        if (test(item)) return item;
        const kids = item.children ?? [];
        for (let i = 0; i < kids.length; ++i) { const hit = find(kids[i], test); if (hit) return hit; }
        return null;
    }
    function badge(item) { return find(item, c => c.tone !== undefined && c.icon !== undefined); }
    function fake(urgency) {
        return Qt.createQmlObject(`import QtQuick
            QtObject {
                property bool closed: false
                property int urgency: ${urgency}
                property string summary: "%LONG%"
                property string appName: "%LONG%"
                property string timeStr: "12:04"
                property string image: ""
                property string body: "%LONG%"
                property var actions: []
                property bool interactionActive: false
                function lock(item) {}
                function unlock(item) {}
                function close() { closed = true; }
            }`, root);
    }

    Window {
        width: 900; height: 700; visible: true; color: CortetsuDesign.colorSumi
        Column {
            x: 16; y: 16; spacing: 16; width: 360
            N.Notification { id: normal; width: 360; modelData: root.fake(1); props: ({}); expanded: false; screenState: null }
            N.Notification { id: urgent; width: 360; modelData: root.fake(2); props: ({}); expanded: true; screenState: null }
            T.ToastItem { id: toast; toast: ({ type: 0, icon: "", title: "%LONG%", message: "%LONG%" }) }
            T.ToastItem { id: urgentToast; toast: ({ type: 2, icon: "warning", title: "Disco al 93 %", message: "" }) }
        }
    }

    readonly property var steps: [
        () => normal.width > 0 && toast.width > 0,
        () => {
            verify(Qt.colorEqual(badge(normal).tone, CortetsuDesign.colorIndicator), "normal notification badge uses the indicator tone");
            verify(Qt.colorEqual(badge(urgent).tone, CortetsuDesign.colorVermillion), "urgent notification badge is vermillion");
            verify(Qt.colorEqual(badge(toast).tone, CortetsuDesign.colorIndicator), "toast badge uses the indicator tone");
            verify(Qt.colorEqual(badge(urgentToast).tone, CortetsuDesign.colorVermillion), "urgent toast badge is vermillion");
            verify(badge(toast).icon === "info", "a toast without an icon shows info");
            for (const [card, name] of [[normal, "normal"], [urgent, "urgent"], [toast, "toast"]]) {
                const text = find(card, c => c.text !== undefined && c.text.startsWith("Actualización") && c.visible);
                const end = text.mapToItem(card, text.width, 0).x;
                verify(end <= card.width, `${name}: long text ends at ${end}, card is ${card.width}`);
            }
            grab(normal, "normal"); grab(urgent, "urgent"); grab(toast, "toast"); grab(urgentToast, "toast-urgent");
            normal.modelData.close();
            return true; },
        () => normal.opacity === 0,
        () => { verify(normal.opacity === 0, "a closed notification fades out"); return true; }
    ]

    Timer {
        interval: 80; repeat: true; running: true
        onTriggered: {
            if (root.step >= root.steps.length) { console.log(`NOTICE_RUNTIME_PASS ${root.checks}`); Qt.quit(); return; }
            if (root.steps[root.step]()) root.step++;
        }
    }
    Timer { interval: 10000; running: true; onTriggered: { console.log("NOTICE_FAIL timeout at", root.step); Qt.quit(); } }
}
""".replace("%LONG%", LONG)

with tempfile.TemporaryDirectory(prefix="cortetsu-notice-") as temporary:
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
           "XDG_STATE_HOME": str(home / ".local/state"),
           "CORTETSU_RENDER_DIR": os.environ.get("CORTETSU_RENDER_DIR", "")}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert "NOTICE_RUNTIME_PASS 9" in output, output
    for marker in ("NOTICE_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type"):
        assert marker not in output, output

print("PASS: notification and toast badges use the shared tones, long text stays inside and closing fades out")
