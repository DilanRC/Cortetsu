#!/usr/bin/env python3
"""Orbital's playback panel loads and its colour button follows the rules.

SteamPlayback runs in Quickshell (offscreen) on a copy of the shell with the
Orbital and CortetsuColours singletons replaced by doubles: no supervisor,
no renderer, no scheme is written. The button that takes the theme colours
from an animated wallpaper must only work for the wallpaper that is active
on this monitor, with a preview image, while the scheme follows the
wallpaper; and it must send exactly that preview path.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

ORBITAL = """pragma Singleton
import Quickshell

Singleton {
    property bool available: true
    property var backends: [{ id: "almamu-wayland", available: true }]
    property var inspections: ({ "/w/1": { supported: true, capabilities: {} } })
    property var preferences: ({ monitors: {}, previous: {}, favorites: [], collections: {}, playlists: {}, profiles: {} })
    property var outputs: ({})
    property string error: ""
    property string errorCode: ""
    property string colourState: ""
    property string colourError: ""
    property var adopted: []
    function output(monitor: string): var { return outputs[monitor] || {}; }
    function ensure(): void {}
    function inspect(location: string): void {}
    function apply(monitor: string, selection: var): bool { return true; }
    function send(message: var): bool { return true; }
    function adoptColours(preview: string): bool { adopted = adopted.concat([preview]); return true; }
}
"""

COLOURS = """pragma Singleton
import Quickshell

Singleton { property string origin: "wallpaper" }
"""

SHELL = """import QtQuick
import Quickshell
import "modules"
import "modules/wallpaper"
import "services"

ShellRoot {
    id: shell
    property int failures: 0
    function check(ok, reason) { if (!ok) { failures++; console.log("COLOURS_FAIL", reason); } }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const child of item.children ?? []) { const found = find(child, name); if (found) return found; }
        return null;
    }

    FloatingWindow {
        width: 900; height: 900; visible: true
        SteamPlayback {
            id: panel
            width: 860
            monitor: "eDP-1"
            assets: "/assets"
            entry: ({ location: "/w/1", title: "Uno", type: "scene", preview: "/w/1/preview.gif", properties: {} })
        }
    }

    Timer {
        interval: 300; running: true
        onTriggered: {
            const button = shell.find(panel, "orbitalColours");
            shell.check(button !== null, "the colour button exists");
            shell.check(button.disabled, "stopped on this monitor: no colours to take");

            Orbital.outputs = ({ "eDP-1": { state: "active", selection: { location: "/w/1" } } });
            shell.check(!button.disabled, "active here, with a preview and a wallpaper scheme: offered");
            button.clicked();
            shell.check(JSON.stringify(Orbital.adopted) === JSON.stringify(["/w/1/preview.gif"]),
                `sends exactly the preview path (${JSON.stringify(Orbital.adopted)})`);

            Orbital.outputs = ({ "eDP-1": { state: "active", selection: { location: "/w/other" } } });
            shell.check(button.disabled, "another wallpaper is the one playing: not offered");

            Orbital.outputs = ({ "eDP-1": { state: "active", selection: { location: "/w/1" } } });
            CortetsuColours.origin = "manual";
            shell.check(button.disabled && button.tooltipText.includes("Esquema según el fondo"),
                `a manual scheme names the switch to turn on (${button.tooltipText})`);
            CortetsuColours.origin = "wallpaper";

            CortetsuConfig.smartScheme = false;
            shell.check(button.disabled, "Smart scheme off: not offered");
            CortetsuConfig.smartScheme = true;

            panel.entry = ({ location: "/w/1", title: "Uno", type: "scene", preview: null, properties: {} });
            shell.check(button.disabled && button.tooltipText.includes("portada"), "no preview image: not offered, and says why");

            panel.entry = ({ location: "/w/1", title: "Uno", type: "scene", preview: "/w/1/preview.gif", properties: {} });
            Orbital.colourState = "busy";
            shell.check(button.disabled && button.label.includes("Aplicando"), "a request in flight blocks a second one");

            console.log(shell.failures === 0 ? "COLOURS_PASS" : "COLOURS_DONE");
            Qt.quit();
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-orbital-colours-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        shutil.copytree(ROOT / name, folder / name)
    for item in (ROOT / "base/utils").iterdir():
        target = folder / "utils" / item.name
        if not target.exists():
            (shutil.copytree if item.is_dir() else shutil.copy)(item, target)
    (folder / "services/Orbital.qml").write_text(ORBITAL)
    (folder / "services/CortetsuColours.qml").write_text(COLOURS)
    (folder / "shell.qml").write_text(SHELL)
    config = folder / "home/.config/cortetsu"
    config.mkdir(parents=True)
    (config / "preferences.json").write_text(json.dumps({"schema": 1, "smartScheme": True}))
    env = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(folder / "home"),
           "XDG_CONFIG_HOME": str(folder / "home/.config"), "XDG_STATE_HOME": str(folder / "state"),
           "XDG_CACHE_HOME": str(folder / "cache")}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    assert "COLOURS_PASS" in output, output
    for marker in ("TypeError", "ReferenceError", "is not a type", "Binding loop"):
        assert marker not in output, output

print("PASS: Orbital's colour button is offered only for the wallpaper playing here, with a preview, while the scheme follows the wallpaper, and sends that preview")
