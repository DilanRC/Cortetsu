#!/usr/bin/env python3
"""The lock screen card on the offscreen platform, with a fake PAM object.

LockCard only reads PAM state; keys, focus and the release stay in
LockSurface and are covered by test-cortetsu-lock-runtime.py. This checks
what the card shows: the empty field, typed dots, a rejected attempt (red
edge, message, a shake that ends where it started), Caps Lock inside the
field and a long user name that stays inside the card.

Set CORTETSU_RENDER_DIR to keep a PNG of each state.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "modules/lock"
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property bool busy: false
    property int grabs: 0
    property real shakeSeen: 0
    property int settle: 0
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("LOCK_FAIL", reason); else checks++; }
    function grab(name) {
        if (!renderDir) { grabs++; return; }
        card.grabToImage(r => { r.saveToFile(`${renderDir}/lock-${name}.png`); grabs++; });
    }
    function find(item, test) {
        if (test(item)) return item;
        for (const kid of item.children ?? []) { const hit = find(kid, test); if (hit) return hit; }
        return null;
    }
    function shown(text) { return find(card, c => c.visible && c.opacity > 0 && c.text === text) !== null; }

    QtObject {
        id: pam
        property int state: 0
        property string buffer: ""
        property bool checking: false
        signal flashMsg()
    }

    Window {
        id: window
        width: 1280; height: 800; visible: true; color: CortetsuDesign.colorSumi
        LockCard {
            id: card
            anchors.fill: parent
            pam: pam
            userLabel: "dilan"
            keyboardLayout: "Español (Latinoamérica)"
            batteryLabel: "Batería 86 %"
            networkLabel: "Casa"
        }
    }

    // The field's x offset while the shake runs.
    readonly property real nudge: card.passwordField.transform[0]?.x ?? 0
    onNudgeChanged: shakeSeen = Math.max(shakeSeen, Math.abs(nudge))

    readonly property var steps: [
        () => window.active && card.passwordField.width > 0,
        () => { verify(card.markPhase === "Ascended", `a locked session shows Ascended (${card.markPhase})`);
                verify(shown("Contraseña"), "an empty field says what goes in it");
                verify(!find(card, c => c.objectName === "lockCapsLock").visible, "no Caps Lock badge while it is off");
                grab("empty"); return true; },
        () => grabs === 1,
        () => { pam.buffer = "secret"; return true; },
        () => { verify(card.markPhase === "Ascended", "typing does not change the mark");
                verify((() => { const dots = find(card, c => c.objectName === "lockTypedDots"); return dots && dots.visible && dots.children.length >= 6; })(), "typed characters show as one dot each");
                grab("typing"); return true; },
        () => grabs === 2,
        // Enter: PAM takes the buffer and is checking; a previous error must not show.
        () => { pam.state = 3; pam.buffer = ""; pam.checking = true; return true; },
        () => { verify(shown("Comprobando…") && !shown("Contraseña incorrecta. Inténtalo de nuevo."),
                       "while PAM checks, the field says so and hides the old error");
                pam.checking = false; pam.flashMsg(); return true; },
        () => card.passwordField.transform[0].x === 0 && root.shakeSeen > 0,
        () => { verify(root.shakeSeen >= 6, `a rejected attempt shakes the field (${root.shakeSeen} px)`);
                verify(Qt.colorEqual(card.passwordField.border.color, CortetsuDesign.colorVermillion), "the field edge turns vermillion");
                verify(shown("Contraseña incorrecta. Inténtalo de nuevo."), "the message says what failed");
                verify(card.markPhase === "Monster", `a rejected attempt shows Monster (${card.markPhase})`);
                grab("failed"); return true; },
        () => grabs === 3,
        // Too many attempts used to be shadowed by the wrong-password text.
        () => { pam.state = 2; return true; },
        () => { verify(shown("Demasiados intentos. Espera antes de volver a probar.")
                       && !shown("Contraseña incorrecta. Inténtalo de nuevo."), "too many attempts has its own message");
                verify(card.markPhase === "Monster" && Qt.colorEqual(card.passwordField.border.color, CortetsuDesign.colorVermillion),
                       "and stays in the rejected state");
                pam.state = 1; return true; },
        () => { verify(shown("La autenticación no está disponible") && card.markPhase === "Ascended"
                       && !Qt.colorEqual(card.passwordField.border.color, CortetsuDesign.colorVermillion),
                       "an unavailable backend is not presented as a wrong password");
                pam.state = 0; card.accepted = true; return true; },
        () => { verify(card.markPhase === "Cosmic", "Cosmic shows only once PAM accepted");
                grab("accepted"); return true; },
        () => grabs === 4,
        () => { card.accepted = false; pam.state = 3; return true; },
        () => { verify(card.markPhase === "Monster", "acceptance is the only way to Cosmic");
                // Reduced motion: the rejection is still shown, nothing moves.
                CortetsuDesign.reducedMotion = true; root.shakeSeen = 0; pam.flashMsg(); return true; },
        () => { root.settle += 1; return root.settle > 5; },
        () => { verify(root.shakeSeen === 0 && shown("Contraseña incorrecta. Inténtalo de nuevo."),
                       `reduced motion shows the rejection without the shake (${root.shakeSeen} px)`);
                CortetsuDesign.reducedMotion = false; return true; },
        () => { root.shakeSeen = 0; pam.flashMsg(); return true; },
        () => root.shakeSeen > 0 && card.passwordField.transform[0].x === 0,
        () => { verify(true, "a second rejection shakes again");
                pam.state = 0; card.capsLock = true;
                card.userLabel = "Nombre de usuario extremadamente largo para una pantalla de bloqueo".repeat(2);
                window.width = 640; window.height = 720; return true; },
        () => { const badge = find(card, c => c.objectName === "lockCapsLock");
                verify(badge.visible && badge.text === "Bloq Mayús", "Caps Lock shows inside the field");
                const name = find(card, c => c.text === card.userLabel);
                const end = name.mapToItem(card, name.width, 0).x;
                verify(end <= 640, `a long user name stays on screen (${end})`);
                grab("caps-narrow"); return true; },
        () => grabs === 5
    ]

    Timer {
        interval: 60; repeat: true; running: true
        onTriggered: {
            if (root.busy) return;
            if (root.step >= root.steps.length) { console.log(`LOCK_CARD_PASS ${root.checks}`); Qt.quit(); return; }
            root.busy = true;
            try { if (root.steps[root.step]()) root.step++; }
            catch (error) { console.log("LOCK_FAIL step", root.step, error); Qt.quit(); }
            root.busy = false;
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.log("LOCK_FAIL timeout at", root.step); Qt.quit(); } }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-lock-card-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        if (ROOT / name).exists():
            shutil.copytree(ROOT / name, folder / name)
    shutil.copy(ROOT / "base/services/VPN.qml", folder / "services/VPN.qml")
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config").mkdir(parents=True)
    # offscreen draws no shader effects (the mark is one). To see it, point
    # WAYLAND_DISPLAY at a headless GL compositor and set CORTETSU_TEST_QPA=wayland.
    platform = os.environ.get("CORTETSU_TEST_QPA", "offscreen")
    env = {**os.environ, "QT_QPA_PLATFORM": platform, "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_STATE_HOME": str(home / ".local/state"),
           "CORTETSU_RENDER_DIR": os.environ.get("CORTETSU_RENDER_DIR", "")}
    if platform == "offscreen":
        env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert "LOCK_CARD_PASS 19" in output, output
    for marker in ("LOCK_FAIL", "TypeError", "ReferenceError", "Binding loop", "is not a type"):
        assert marker not in output, output

print("PASS: the lock card shows the empty, typing, rejected, locked-out, unavailable and accepted states "
      "with the mark each one calls for, shakes on a rejection unless motion is reduced, "
      "keeps Caps Lock in the field and a long name on screen")
