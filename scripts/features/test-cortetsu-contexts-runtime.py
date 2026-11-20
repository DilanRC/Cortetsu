#!/usr/bin/env python3
"""CortetsuContexts against the real CortetsuConfig, in Quickshell (offscreen).

Do not disturb, game mode, Orbital, the toaster and the automation
coordinator are doubles that record what they are asked: nothing reaches
the desktop. No context here touches the power profile, which would reach
power-profiles-daemon over D-Bus.

Checks: activation writes through the owners; deactivation gives back only
what still holds the context's value; switching contexts with an
asynchronous setting (do not disturb) re-applies it; a domain owned by the
coordinator is left alone and said; and a new process keeps the context
active and restores Orbital's hold from contexts.json.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

DOUBLES = {
    # setDnd is answered later by the helper: dnd does not change here.
    "Notifs.qml": 'pragma Singleton\nimport Quickshell\nSingleton { property bool dnd: false; property var calls: []\n'
                  '    function setDnd(on: bool): void { calls = calls.concat(["dnd:" + on]); } }\n',
    "GameMode.qml": 'pragma Singleton\nimport Quickshell\nSingleton { property var desired: null; property bool enabled: false; property var calls: []\n'
                    '    function setEnabled(on: bool): void { desired = on; calls = calls.concat(["game:" + on]); } }\n',
    "Orbital.qml": 'pragma Singleton\nimport Quickshell\nSingleton { property bool hold: false }\n',
    "CortetsuToaster.qml": 'pragma Singleton\nimport Quickshell\nSingleton { property var toasts: []\n'
                           '    function toast(title, message, icon, type = 0) { toasts = toasts.concat([message]); } }\n',
    "ShellState.qml": 'pragma Singleton\nimport Quickshell\nSingleton { property var owned: []\n'
                      '    property var shellRoot: ({ policyBridge: { activation: domain => ({ enabled: owned.includes(domain) }) } }) }\n',
}

SHELL = """import QtQuick
import Quickshell
import "modules"
import "services"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    readonly property string scenario: Quickshell.env("CONTEXTS_SCENARIO")
    function verify(value, reason) { if (!value) console.log("CONTEXTS_FAIL", reason); else checks++; }

    readonly property var first: [
        () => CortetsuConfig.loaded && CortetsuContexts.loaded,
        () => {
            verify(CortetsuContexts.activeId === "", "nothing active on a fresh state");
            verify(CortetsuContexts.activate("gaming"), "Gaming activates");
            verify(GameMode.calls.join() === "game:true", `game mode asked on (${GameMode.calls})`);
            verify(Notifs.calls.join() === "dnd:true", `do not disturb asked on (${Notifs.calls})`);
            verify(Orbital.hold === true, "animated wallpapers held");
            verify(CortetsuConfig.visualiserEnabled === false && CortetsuConfig.bottomHub.spacing === "compact"
                && CortetsuConfig.bottomHub.windowThumbnails === false, "the shell settings changed through CortetsuConfig");
            verify(CortetsuContexts.activeId === "gaming", "Gaming is the active context");
            // The user turns the visualiser back on while Gaming is active.
            CortetsuConfig.visualiserEnabled = true;
            Notifs.dnd = true; GameMode.enabled = true; GameMode.desired = null;
            CortetsuContexts.deactivate();
            verify(CortetsuConfig.visualiserEnabled === true, "a setting the user changed meanwhile stays the user's");
            verify(CortetsuConfig.bottomHub.spacing === "standard" && CortetsuConfig.bottomHub.windowThumbnails === true,
                "the rest comes back");
            verify(Orbital.hold === false, "the hold is released");
            verify(Notifs.calls[Notifs.calls.length - 1] === "dnd:false" && GameMode.calls[GameMode.calls.length - 1] === "game:false", "do not disturb and game mode asked off");
            return true;
        },
        () => {
            // Switching straight from Gaming to a context that also wants do
            // not disturb: the helper has not answered the "off" yet, and the
            // second context must still ask for "on".
            const copy = CortetsuContexts.duplicate("university");
            verify(copy.length > 0 && CortetsuContexts.setSetting(copy, "dnd", true), "an own context with do not disturb");
            Notifs.dnd = false; GameMode.enabled = false; Notifs.calls = [];
            CortetsuContexts.activate("gaming");
            Notifs.dnd = true;
            CortetsuContexts.activate(copy);
            verify(Notifs.calls.join() === "dnd:true,dnd:false,dnd:true", `the second context re-applies do not disturb (${Notifs.calls})`);
            verify(CortetsuContexts.activeId === copy, "the own context is active");
            CortetsuContexts.deactivate();
            return true;
        },
        () => {
            // The coordinator owns game mode: Gaming leaves it and says so.
            ShellState.owned = ["gamemode"];
            GameMode.calls = [];
            CortetsuContexts.activate("gaming");
            verify(GameMode.calls.length === 0, "game mode is the coordinator's");
            verify(CortetsuContexts.skipped.includes("gameMode") && CortetsuContexts.notice.includes("Modo juego"),
                `the notice names what was left (${CortetsuContexts.notice})`);
            ShellState.owned = [];
            return true;
        },
        () => CortetsuConfig.saveState === "saved",
        () => { console.log("CONTEXTS_PASS", root.checks); Qt.quit(); return true; }
    ]

    readonly property var restart: [
        () => CortetsuConfig.loaded && CortetsuContexts.loaded,
        () => {
            verify(CortetsuContexts.activeId === "gaming", "a new process keeps Gaming active");
            verify(Orbital.hold === true, "and holds animated wallpapers again");
            verify(CortetsuContexts.custom.length === 1, "the own context survives");
            CortetsuContexts.deactivate();
            verify(CortetsuContexts.activeId === "" && Orbital.hold === false, "and can still be deactivated");
            console.log("CONTEXTS_PASS", root.checks); Qt.quit(); return true;
        }
    ]

    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            const steps = root.scenario === "restart" ? root.restart : root.first;
            try { if (steps[root.step]()) root.step++; }
            catch (error) { console.log("CONTEXTS_FAIL", error); Qt.quit(); }
        }
    }
    Timer { interval: 20000; running: true; onTriggered: { console.log("CONTEXTS_FAIL timeout at", root.step); Qt.quit(); } }
}
"""


def run(folder: Path, home: Path, scenario: str) -> str:
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(home),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"),
           "XDG_CACHE_HOME": str(home / ".cache"), "CONTEXTS_SCENARIO": scenario}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=60)
    return result.stdout + result.stderr


with tempfile.TemporaryDirectory(prefix="cortetsu-contexts-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        shutil.copytree(ROOT / name, folder / name)
    for item in (ROOT / "base/utils").iterdir():
        target = folder / "utils" / item.name
        if not target.exists():
            (shutil.copytree if item.is_dir() else shutil.copy)(item, target)
    for name, text in DOUBLES.items():
        (folder / "services" / name).write_text(text)
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".config/cortetsu").mkdir(parents=True)
    (home / ".local/state/cortetsu").mkdir(parents=True)
    (home / ".config/cortetsu/preferences.json").write_text(json.dumps({"schema": 1, "visualiserEnabled": True}))

    output = run(folder, home, "first")
    assert "CONTEXTS_PASS" in output and "CONTEXTS_FAIL" not in output, output
    state = json.loads((home / ".local/state/cortetsu/contexts.json").read_text())
    assert state["active"] == "gaming" and state["applied"].get("orbitalHold") is True, state
    assert "gameMode" in state["skipped"], state

    restarted = run(folder, home, "restart")
    assert "CONTEXTS_PASS" in restarted and "CONTEXTS_FAIL" not in restarted, restarted
    for text in (output, restarted):
        for marker in ("TypeError", "ReferenceError", "is not a type", "Binding loop"):
            assert marker not in text, text

print("PASS: contexts write through their owners, give back only what is still theirs, re-apply asynchronous settings on a switch, leave the coordinator's domains alone and survive a restart")
