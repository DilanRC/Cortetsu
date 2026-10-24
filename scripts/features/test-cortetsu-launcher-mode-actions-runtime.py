#!/usr/bin/env python3
"""Launcher actions that cannot run are offered disabled, with the reason.

The upstream defaults that many configs still carry include "Light" and
"Dark" (command ["setMode", ...]). Cortetsu has no command that switches the
mode of the current scheme: the launcher ran `cortetsu theme set <mode>`,
which does not exist, so choosing them did nothing and said nothing.

The real Actions singleton and CortetsuConfig run in Quickshell (offscreen)
with a temporary HOME whose preferences hold one mode action and one ordinary
action. The runtime tree overlays base/utils the way the build does.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

SHELL = """import QtQuick
import Quickshell
import "modules"
import "modules/launcher/services"
ShellRoot {
    property int waited: 0
    Timer {
        interval: 200; repeat: true; running: true
        onTriggered: {
            if (!CortetsuConfig.loaded && ++parent.waited < 50) return;
            for (const action of Actions.list)
                console.log("ACTION", JSON.stringify({ name: action.name, available: action.available, desc: action.desc }));
            Qt.quit();
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-launcher-actions-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        shutil.copytree(ROOT / name, folder / name)
    for item in (ROOT / "base/utils").iterdir():
        target = folder / "utils" / item.name
        if not target.exists():
            (shutil.copytree if item.is_dir() else shutil.copy)(item, target)
    (folder / "shell.qml").write_text(SHELL)
    config = folder / "home/.config/cortetsu"
    config.mkdir(parents=True)
    (config / "preferences.json").write_text(json.dumps({"schema": 1, "actions": [
        {"name": "Dark", "icon": "dark_mode", "description": "Change the scheme to dark mode", "command": ["setMode", "dark"]},
        {"name": "Lock", "icon": "lock", "description": "Lock the current session", "command": ["loginctl", "lock-session"]},
    ]}))
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(folder / "home"),
           "XDG_CONFIG_HOME": str(folder / "home/.config"), "XDG_STATE_HOME": str(folder / "state"),
           "XDG_CACHE_HOME": str(folder / "cache")}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    actions = {entry["name"]: entry for entry in (json.loads(line.split("ACTION ", 1)[1])
                                                 for line in output.splitlines() if "ACTION {" in line)}
    assert set(actions) == {"Dark", "Lock"}, output
    assert not actions["Dark"]["available"], actions
    assert actions["Dark"]["desc"].startswith("No disponible"), actions
    assert actions["Lock"]["available"] and actions["Lock"]["desc"] == "Lock the current session", actions
    for marker in ("TypeError", "ReferenceError", "is not a type", "Binding loop"):
        assert marker not in output, output

print("PASS: a mode action the shell cannot run is listed disabled with its reason; ordinary actions stay available")
