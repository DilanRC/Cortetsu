#!/usr/bin/env python3
"""Runtime check that the real CortetsuWallpapers catalog only changes when the folder does.

Preferences, colours and the state directory are stand-ins inside a temporary
tree, so the live wallpaper and scheme are never read or written.
"""
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"

CONFIG = """pragma Singleton
import QtQuick
QtObject {
    property string wallpaperDirectory: "/nonexistent"
    property bool smartScheme: false
    property bool useFuzzyWallpapers: false
}
"""

COLOURS = """pragma Singleton
import QtQuick
QtObject {
    function load(data, isPreview) {}
    function clearPreview(): void {}
}
"""

SHELL = """import QtQuick
import Quickshell
import "modules"

ShellRoot {
    id: root
    property int checks: 0
    property int changes: 0
    property int step: 0
    readonly property string walls: Quickshell.env("CORTETSU_WALLPAPERS_DIR")
    function verify(value, reason) { if (!value) { console.log("CATALOG_FAIL", reason); return; } checks++; }

    Connections {
        target: CortetsuWallpapers
        function onListChanged(): void { root.changes++; }
    }

    Timer {
        interval: 400; repeat: true; running: true
        onTriggered: {
            root.step++;
            if (root.step === 1) {
                root.verify(CortetsuWallpapers.list.length === 2, "the first scan fills the catalog");
                root.verify(root.changes === 1, "the first scan changes the catalog once");
                CortetsuWallpapers.reload();
            } else if (root.step === 2) {
                root.verify(root.changes === 1, "rescanning an unchanged folder keeps the catalog");
                Quickshell.execDetached(["touch", `${root.walls}/c.png`]);
            } else if (root.step === 3) {
                CortetsuWallpapers.reload();
            } else if (root.step === 4) {
                root.verify(root.changes === 2, "a new file replaces the catalog");
                root.verify(CortetsuWallpapers.list.length === 3, "the new file is listed");
                console.log("CATALOG_RUNTIME_PASS", root.checks);
                Qt.quit();
            }
        }
    }
}
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-wallpaper-catalog-") as temporary:
    folder = Path(temporary)
    walls = folder / "walls"
    walls.mkdir()
    for name in ("a.png", "b.jpg"):
        (walls / name).write_bytes(b"")
    (folder / "modules").mkdir()
    (folder / "services").mkdir()
    (folder / "assets").mkdir()
    for name in ("CortetsuWallpapers.qml", "CortetsuDesign.js", "CortetsuWallpaperSearch.js"):
        shutil.copy(ROOT / "modules" / name, folder / "modules" / name)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "services/CortetsuColours.qml").write_text(COLOURS)
    (folder / "shell.qml").write_text(SHELL)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "CORTETSU_WALLPAPERS_DIR": str(walls),
             "XDG_STATE_HOME": str(folder / "state")},
        capture_output=True, text=True, timeout=20,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    assert "CATALOG_FAIL" not in output, output
    assert "CATALOG_RUNTIME_PASS 5" in output, output
    for marker in ("TypeError", "ReferenceError"):
        assert marker not in output, output

print("PASS: the wallpaper catalog is replaced only when the folder contents change")
