#!/usr/bin/env python3
"""«Atajos y teclados» per keyboard, in Quickshell with a stand-in helper.

Same scaffolding as test-cortetsu-keyboards-runtime.py. The surface must:
- show which keyboards an application shortcut listens to, by label, and
  mark a name whose keyboard is unplugged;
- send `scope` for «Solo este», «Todos salvo este» and «Todos» with the
  selected keyboard's Hyprland names and the reviewed version;
- run the key test: begin, poll status, show each press, end, refresh keys;
  refuse any change while it runs, and end it when the surface closes;
- propose the applications of a spare key's suggestion without applying.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1] / "cortetsu"
SOURCE = (HERE / "test-cortetsu-keyboards-runtime.py").read_text(encoding="utf-8")
CONFIG = SOURCE.split('CONFIG = """', 1)[1].split('"""', 1)[0]

HELPER = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
home = Path(os.environ["HOME"])
args = sys.argv[1:]
with open(home / "calls", "a") as log:
    log.write(" ".join(args) + "\n")
def out(value):
    print(json.dumps(value)); sys.exit(0)
calls = (home / "calls").read_text().splitlines()
scoped = any(c.startswith("--expect v1 scope app:1 only") for c in calls)
app = {"id": "app:1", "label": "Calc", "chord": "SUPER + ALT + E", "group": "Application", "description": "calc",
       "command": "calc", "appId": "org.example.Calc", "appName": "Calc", "origin": "edited", "editable": True,
       "deletable": True, "resettable": False, "active": True, "conflicts": [], "scopable": True}
if scoped:
    app["devices"] = {"only": True, "names": ["semico-usb-keyboard", "semico-usb-keyboard-consumer-control"]}
else:
    app["devices"] = {"only": False, "names": ["unplugged-kbd"]}
base = {"id": "var:kbBrowser:0", "label": "Browser", "chord": "SUPER + W", "group": "Application",
        "description": "firefox", "command": "firefox", "origin": "default", "editable": True, "deletable": True,
        "resettable": False, "active": True, "conflicts": [], "scopable": False}
keyboard = {"id": "usb:1", "model": "usb:1a2c:2124", "kind": "usb", "label": "SEMICO USB Keyboard",
            "detail": "USB", "ambiguous": False, "hyprlandLinked": True,
            "interfaces": [{"event": "event9", "name": "SEMICO USB Keyboard", "hyprlandName": "semico-usb-keyboard"},
                           {"event": "event10", "name": "SEMICO USB Keyboard Consumer Control",
                            "hyprlandName": "semico-usb-keyboard-consumer-control"}]}
verified = any(c.startswith("probe end") for c in calls)
calc = {"code": 140, "name": "KEY_CALC", "label": "Calculadora", "keysym": "XF86Calculator", "category": "launch",
        "states": ["DECLARED", "VERIFIED", "CANDIDATE"] if verified else ["DECLARED", "CANDIDATE"],
        "confidence": "verified" if verified else "declared", "declaredBy": ["SEMICO USB Keyboard"],
        "suggestion": {"category": "Calculator", "label": "Calculadora"}}
cmd = args[0] if args else ""
if cmd == "watch":
    print(json.dumps({"protocol": 2, "kind": "inventory", "ok": True, "event": "initial", "keyboards": [keyboard],
                      "hyprlandOnly": [], "hyprlandAvailable": True, "fingerprint": "f1"}), flush=True)
    time.sleep(60); sys.exit(0)
if cmd == "keys":
    out({"protocol": 2, "kind": "keys", "ok": True, "devices": [{"device": keyboard, "keys": [calc]}],
         "spare": [dict(calc, device=keyboard["id"], deviceLabel=keyboard["label"])], "fingerprint": "f1"})
if cmd == "bindings":
    out({"protocol": 2, "kind": "bindings", "ok": True, "bindings": [app, base], "version": "v1"})
if cmd == "probe":
    statuses = calls.count("probe status")
    hits = [140] if statuses >= 2 else []
    if args[1] == "begin":
        out({"protocol": 2, "kind": "probe", "ok": True, "active": True, "hits": [], "codes": [140, 148]})
    if args[1] == "status":
        out({"protocol": 2, "kind": "probe", "ok": True, "active": True, "hits": hits})
    out({"protocol": 2, "kind": "probe", "ok": True, "active": False, "hits": [140], "verified": [140]})
if cmd == "--expect":
    out({"ok": True, "message": "Guardado", "snapshot": "/tmp/x"})
out({"ok": False, "error": "unexpected " + " ".join(args)})
'''

SHELL = """import QtQuick
import Quickshell
import "modules/keyboards"
import "modules/keyboards/Model.js" as Model

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property bool shown: true
    function verify(value, reason) { if (!value) { console.log("KEYBOARDS_FAIL", step, reason); return; } checks++; }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children) { const hit = find(child, name); if (hit) return hit; }
        if (item.contentItem) return find(item.contentItem, name);
        return null;
    }

    FloatingWindow {
        id: window
        implicitWidth: 1400; implicitHeight: 900; visible: true
        Content {
            id: page
            anchors.fill: parent
            screen: Quickshell.screens[0]
            screenState: null
            surfaceVisible: root.shown
        }
    }

    Timer {
        interval: 300; repeat: true; running: true
        onTriggered: {
            root.step++;
            const s = root.step;
            const app = page.backend.bindings.find(b => b.id === "app:1");
            if (s === 2) {
                root.verify(Model.scopeText(app.devices, page.backend.keyboards) === "Todos salvo unplugged-kbd (desconectado)",
                            "an unplugged keyboard is named as such");
                page.selectBinding(app);
                root.verify(root.find(page, "scope-only").disabled, "no keyboard chosen: nothing to target");
                page.deviceId = "usb:1";
            } else if (s === 3) {
                root.verify(!root.find(page, "scope-only").disabled, "a linked keyboard can be targeted");
                root.find(page, "scope-only").clicked();
            } else if (s === 5) {
                const scoped = page.backend.bindings.find(b => b.id === "app:1");
                root.verify(Model.scopeText(scoped.devices, page.backend.keyboards) === "Solo en SEMICO USB Keyboard",
                            "the new scope is listed by label: " + JSON.stringify(scoped.devices));
                root.verify(root.find(page, "scope-only").disabled, "the current scope is not offered again");
                page.selectBinding(page.backend.bindings.find(b => b.id === "var:kbBrowser:0"));
                root.verify(root.find(page, "scope-all") === null || !root.find(page, "scope-all").visible,
                            "base shortcuts take no scope");
                page.currentTab = 2;
            } else if (s === 6) {
                root.find(page, "startProbe").clicked();
            } else if (s === 8) {
                root.verify(page.probing, "the key test is running");
                page.selectBinding(page.backend.bindings.find(b => b.id === "app:1"));
                page.startCapture();
                root.verify(page.flow.phase === "idle", "no capture during the key test");
            } else if (s === 10) {
                root.verify(page.probeHits.indexOf(140) >= 0, "a press shows while testing: " + JSON.stringify(page.backend.probe));
                root.find(page, "endProbe").clicked();
            } else if (s === 12) {
                root.verify(!page.probing && page.backend.probeSummary.indexOf("1") >= 0, "the test ended: " + page.backend.probeSummary);
                root.verify((page.spareRows[0].states ?? []).indexOf("VERIFIED") >= 0, "keys reloaded with the press");
                page.selectKey(page.spareRows[0]);
                const apps = Model.suggestedApps(page.selectedKey.suggestion,
                                                 [{ id: "calc", name: "Calc", categories: ["Calculator"], execString: "calc" }]);
                root.verify(apps.length === 1, "the suggestion finds calculators");
                page.assignApp(apps[0]);
                root.verify(page.flow.phase === "review", "a suggestion is only a proposal");
                page.dispatch({ type: "cancel" });
                root.find(page, "startProbe").clicked();
            } else if (s === 14) {
                root.verify(page.probing, "a second test runs");
                root.shown = false;
            } else if (s === 17) {
                console.log("KEYBOARDS_DEVICES_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-keyboards-devices-") as temporary:
    folder = Path(temporary)
    home = folder / "home"
    (home / ".local/bin").mkdir(parents=True)
    helper = home / ".local/bin/cortetsu-keybinds"
    helper.write_text(HELPER)
    helper.chmod(0o700)
    for name in ("components", "theme", "modules", "utils", "services"):
        shutil.copytree(ROOT / name, folder / name, symlinks=True)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home)},
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert "KEYBOARDS_FAIL" not in output, output
    assert "KEYBOARDS_DEVICES_PASS" in output, output
    for marker in ("TypeError", "ReferenceError", "Binding loop", "is not a type", "Unable to assign",
                   "Cannot create delegate", "Required property"):
        assert marker not in output, output
    calls = (home / "calls").read_text().splitlines()
    assert "--expect v1 scope app:1 only semico-usb-keyboard semico-usb-keyboard-consumer-control" in calls, calls
    assert calls.count("probe begin usb:1 60000") == 2, calls
    assert calls.count("probe status") >= 2, calls
    assert calls.count("probe end usb:1") == 2, "the closed surface ended the second test: " + str(calls)
    assert not any(c.startswith("--expect") and "add-app" in c for c in calls), "a suggestion was applied"
    assert not any(c.startswith("capture") for c in calls), calls

print("PASS: «Atajos y teclados» limita atajos a un teclado por su nombre en Hyprland, prueba teclas sin "
      "permitir cambios a la vez, las marca comprobadas y propone aplicaciones sin aplicarlas")
