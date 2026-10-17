#!/usr/bin/env python3
"""«Atajos y teclados» end to end in Quickshell, with a stand-in helper.

The real Content.qml runs offscreen. The helper under HOME records every
call and answers like cortetsu-keybinds, so no Hyprland bind is read or
written. The test drives the capture flow through handleKey(), the function
Keys.onPressed calls, and checks the calls the surface makes:
- capture begin before listening, capture end before review, cancel, close
  and timeout;
- a conflicting chord stops at review; a valid one is applied only after an
  explicit confirm, with the version its preview showed (--expect);
- a spare key is assigned to an application without recording;
- a failed capture begin never leaves the surface listening.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

CONFIG = """pragma Singleton
import QtQuick
QtObject { property bool transparencyEnabled: false; property bool useTwelveHourClock: false }
"""

HELPER = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
home = Path(os.environ["HOME"])
args = sys.argv[1:]
with open(home / "calls", "a") as log:
    log.write(" ".join(args) + "\n")
def out(value):
    print(json.dumps(value)); sys.exit(0)
binding = {"id": "var:kbSession:0", "label": "Session", "chord": "CTRL + SUPER + Delete", "group": "Cortetsu",
           "description": "Session", "command": "", "origin": "default", "editable": True, "deletable": True,
           "resettable": True, "active": True, "conflicts": []}
keyboard = {"id": "usb:1a2c:2124@1-2", "model": "usb:1a2c:2124", "kind": "usb", "label": "SEMICO USB Keyboard",
            "detail": "USB 1a2c:2124", "ambiguous": False, "hyprlandLinked": True,
            "interfaces": [{"event": "event9", "name": "SEMICO USB Keyboard", "bus": 3, "vendor": 6700, "product": 8484,
                            "hyprlandName": "semico-usb-keyboard"}]}
calc = {"code": 140, "name": "KEY_CALC", "label": "Calculadora", "keysym": "XF86Calculator", "category": "launch",
        "states": ["DECLARED", "CANDIDATE"], "confidence": "declared", "declaredBy": ["SEMICO USB Keyboard"]}
cmd = args[0] if args else ""
if cmd == "watch":
    print(json.dumps({"protocol": 2, "kind": "inventory", "ok": True, "event": "initial", "keyboards": [keyboard],
                      "hyprlandOnly": [], "hyprlandAvailable": True, "fingerprint": "f1"}), flush=True)
    time.sleep(60); sys.exit(0)
if cmd == "keys":
    out({"protocol": 2, "kind": "keys", "ok": True, "devices": [{"device": keyboard, "keys": [calc]}],
         "spare": [dict(calc, device=keyboard["id"], deviceLabel=keyboard["label"])], "fingerprint": "f1"})
if cmd == "bindings":
    out({"protocol": 2, "kind": "bindings", "ok": True, "bindings": [binding], "version": "v1"})
if cmd == "capture":
    begins = (home / "calls").read_text().splitlines().count("capture begin 5600")
    if args[1] == "begin" and begins == 6:
        out({"protocol": 2, "kind": "capture", "ok": False, "error": {"code": "capture-unavailable", "message": "recarga Hyprland"}})
    out({"protocol": 2, "kind": "capture", "ok": True, "active": args[1] == "begin",
         "submap": "cortetsu-capture" if args[1] == "begin" else ""})
if cmd == "preview":
    chord = args[-1].upper().replace("SHIFT + SUPER", "SHIFT + SUPER")
    taken = args[-1] == "SHIFT + SUPER + K"
    out({"protocol": 2, "kind": "preview", "ok": True, "id": args[2] if args[1] == "set" else "", "label": "Session",
         "before": binding["chord"] if args[1] == "set" else "", "after": args[-1], "valid": not taken,
         "conflict": taken, "problem": "SHIFT + SUPER + K ya es «Lanzador»" if taken else None, "version": "v1"})
if cmd == "--expect":
    out({"ok": True, "chord": args[-1], "message": "Guardado · " + args[-1], "snapshot": "/tmp/x"})
out({"ok": False, "error": "unexpected " + " ".join(args)})
'''

SHELL = """import QtQuick
import Quickshell
import "modules/keyboards"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property bool shown: true
    function verify(value, reason) { if (!value) { console.log("KEYBOARDS_FAIL", step, reason); return; } checks++; }
    function phase() { return page.flow.phase; }

    FloatingWindow {
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
            if (s === 2) {
                root.verify(page.backend.bindings.length === 1 && page.backend.keyboards.length === 1, "inventory and bindings load");
                root.verify(page.backend.keysymByScanCode[148] === "XF86Calculator", "keysyms by scan code");
                root.verify(page.spareRows.length === 1, "the spare key is listed");
                page.selectBinding(page.backend.bindings[0]);
                page.startCapture();
                root.verify(root.phase() === "listening", "Editar starts recording at once");
            } else if (s === 3) {
                page.handleKey(Qt.Key_Meta, Qt.MetaModifier, 133);
                root.verify(page.flow.held.join() === "SUPER", "held modifiers are echoed");
                page.handleKey(Qt.Key_A, Qt.NoModifier, 38);
                root.verify(root.phase() === "listening" && page.flow.message.length > 0, "a bare key is refused");
                page.handleKey(Qt.Key_K, Qt.MetaModifier | Qt.ShiftModifier, 45);
                root.verify(root.phase() === "recovering", "the submap is released before review");
            } else if (s === 5) {
                root.verify(root.phase() === "conflict", "a taken chord stops at review: " + root.phase());
                root.verify(page.flow.message.indexOf("Lanzador") >= 0, "the conflict names the other action");
                page.startCapture();
            } else if (s === 6) {
                page.handleKey(Qt.Key_J, Qt.MetaModifier, 44);
            } else if (s === 8) {
                root.verify(root.phase() === "review" && page.flow.preview.valid, "a free chord is ready to confirm");
            } else if (s === 9) {
                page.dispatch({ type: "confirm" });
                root.verify(root.phase() === "applying", "confirm applies");
            } else if (s === 11) {
                root.verify(root.phase() === "verified", "success after the helper verified: " + root.phase());
                page.startCapture();
            } else if (s === 12) {
                page.handleKey(Qt.Key_Escape, Qt.NoModifier, 9);
            } else if (s === 14) {
                root.verify(root.phase() === "cancelled", "Escape cancels");
                page.startCapture();
            } else if (s === 15) {
                root.shown = false;
            } else if (s === 17) {
                root.verify(root.phase() === "cancelled", "closing the surface cancels: " + root.phase());
                root.shown = true;
                page.currentTab = 2; // the key rows render too
                page.selectKey(page.spareRows[0]);
                page.assignApp({ id: "org.example.Calc", name: "Calc", execString: "calc" });
                root.verify(root.phase() === "review", "a spare key goes straight to review");
            } else if (s === 18) {
                // A second application for the same key is previewed again.
                page.assignApp({ id: "org.example.Other", name: "Other", execString: "other" });
            } else if (s === 19) {
                root.verify(page.flow.preview?.valid === true, "the second choice was previewed");
                page.dispatch({ type: "confirm" });
            } else if (s === 21) {
                root.verify(root.phase() === "verified", "the app shortcut is applied: " + root.phase());
                page.selectBinding(page.backend.bindings[0]);
                page.startCapture();
            } else if (s === 22) {
                // The timeout is shortened by the test to 600 ms.
            } else if (s === 25) {
                root.verify(root.phase() === "cancelled", "the capture times out: " + root.phase());
                page.startCapture(); // the stand-in refuses the sixth begin
            } else if (s === 28) {
                root.verify(root.phase() === "failed", "a refused capture begin never listens: " + root.phase());
                console.log("KEYBOARDS_RUNTIME_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-keyboards-runtime-") as temporary:
    folder = Path(temporary)
    home = folder / "home"
    (home / ".local/bin").mkdir(parents=True)
    helper = home / ".local/bin/cortetsu-keybinds"
    helper.write_text(HELPER)
    helper.chmod(0o700)
    for name in ("components", "theme", "modules", "utils", "services"):
        shutil.copytree(ROOT / name, folder / name, symlinks=True)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    backend = folder / "modules/keyboards/KeyboardsBackend.qml"
    backend.write_text(backend.read_text().replace("captureTimeoutMs: 15000", "captureTimeoutMs: 600"))
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")],
                            env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home)},
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert "KEYBOARDS_FAIL" not in output, output
    assert "KEYBOARDS_RUNTIME_PASS" in output, output
    for marker in ("TypeError", "ReferenceError", "Binding loop", "is not a type", "Unable to assign",
                   "Cannot create delegate", "Required property"):
        assert marker not in output, output
    calls = (home / "calls").read_text().splitlines()
    begins = calls.count("capture begin 5600")
    ends = calls.count("capture end")
    assert begins == 6 and ends >= 5, calls
    assert "preview set var:kbSession:0 SHIFT + SUPER + K" in calls, calls
    assert "--expect v1 set var:kbSession:0 SUPER + J" in calls, calls
    assert not any(call.startswith("--expect v1 set var:kbSession:0 SHIFT + SUPER + K") for call in calls), calls
    assert "preview add-app XF86Calculator" in calls, calls
    assert calls.count("preview add-app XF86Calculator") == 2, calls
    assert "--expect v1 add-app org.example.Other Other other XF86Calculator" in calls, calls
    assert not any("org.example.Calc" in call for call in calls if call.startswith("--expect")), calls
    # Every begin is followed by an end before the next begin.
    open_capture = False
    for call in calls:
        if call == "capture begin 5600":
            assert not open_capture, f"two captures without an end: {calls}"
            open_capture = True
        elif call == "capture end":
            open_capture = False
    assert not open_capture, calls

print("PASS: «Atajos y teclados» graba, revisa, rechaza conflictos, aplica solo tras confirmar con la versión "
      "revisada y suelta el teclado al cancelar, cerrar, agotar el tiempo o fallar")
