#!/usr/bin/env python3
"""Runtime check of the real Wallpaper Orbital against a generated library.

The real Content.qml, orbit model and CortetsuWallpapers service run inside
Quickshell on the offscreen platform. Preferences, colours and the state
directory are stand-ins in a temporary tree and the wallpaper helper is a
no-op on PATH, so the live wallpaper and scheme are never read or written.

Set CORTETSU_RENDER_DIR to keep a PNG of each state for visual review. The
offscreen platform has no shader effects, so masked images come out blank;
point WAYLAND_DISPLAY at a headless compositor and set CORTETSU_TEST_QPA=wayland
to render them.
"""
import os
import shutil
import struct
import subprocess
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")

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
    readonly property var palette: ({ m3primary: "#b8a4ff" })
    function load(data, isPreview) {}
    function clearPreview(): void {}
}
"""

SETTINGS = """pragma Singleton
import QtQuick
QtObject {
    property string selected: ""
    function select(id) { selected = id; }
}
"""

# The real one opens a layer-shell window, which the offscreen platform lacks.
IDLE_INHIBITOR = """pragma Singleton
import QtQuick
QtObject { property bool enabled: false }
"""

SHELL = """import QtQuick
import QtQuick.Window
import Quickshell
import "modules"
import "modules/wallpaper"
import "services"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property string kept: ""
    readonly property string walls: Quickshell.env("CORTETSU_WALLPAPERS_DIR")
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    readonly property bool emptyRun: Quickshell.env("ORBITAL_EMPTY") === "1"
    function verify(value, reason) { if (!value) { console.log("ORBITAL_FAIL", reason); return; } checks++; }
    function render(name) {
        if (renderDir)
            content.grabToImage(result => result.saveToFile(`${renderDir}/${name}.png`));
    }

    QtObject {
        id: retained
        property bool wallpaperManager: true
        function setRetained(name, value) { if (name === "wallpaperManager") wallpaperManager = value; }
    }
    QtObject {
        id: screenState
        property var cortetsuState: retained
        property bool settings: false
    }

    Window {
        width: 1280; height: 800; visible: true; color: "#15131c"
        Content { id: content; anchors.fill: parent; screen: null; screenState: screenState }
    }

    readonly property var populated: [
        () => content.openManager(),
        () => {
            verify(content.entries.length === 14, "the library is read");
            verify(content.categoryCounts.map(c => `${c.name}:${c.count}`).join(",") === "ALL:14,noche:4,paisajes:8,Sin categoría:2", "categories carry their counts");
            verify(content.currentPath === `${walls}/paisajes/p3.png`, "the applied wallpaper is selected on open");
            verify(content.orbitEntries.length === (content.arcHalf + 1) * 2 + 1, "the arc holds one window plus a hidden slot per side");
            verify(content.presentationReady, "the stage and its neighbours are decoded before presenting");
            render("orbit");
        },
        () => content.requestMove(1),
        () => {
            verify(content.currentPath === `${walls}/paisajes/p4.png`, "a move selects the neighbour");
            verify(content.windowIndex === content.currentIndex && content.orbitPhase === 0 && !content.animating, "the arc re-anchors when the turn ends");
            verify(content.previewActive && CortetsuWallpapers.showPreview, "the settled candidate is previewed");
            verify(content.currentStateLabel === "Vista previa", "the stage names the preview state");
            render("preview");
        },
        () => content.query = "noche",
        () => {
            verify(content.filteredEntries.length === 4, "search narrows the visible set");
            verify(!CortetsuWallpapers.showPreview, "changing the filter drops the preview");
            content.query = "zzz";
        },
        () => {
            verify(content.noResults && content.currentPath === "", "a search without matches is its own state");
            render("no-results");
        },
        () => content.query = "",
        () => {
            verify(content.currentPath === `${walls}/paisajes/p3.png`, "clearing the search returns to the applied wallpaper");
            content.cycleCategory(1);
        },
        () => {
            verify(content.selectedCategory === "noche" && content.filteredEntries.length === 4, "the keyboard walks the categories");
            content.selectCategory("paisajes");
            content.select(6);
        },
        () => {
            verify(content.currentPath === `${walls}/paisajes/p6.png`, "a jump past the arc lands on its target");
            verify(content.windowIndex === content.currentIndex, "a jump re-anchors at once");
            content.toggleGrid();
        },
        () => {
            verify(content.gridMode, "the grid replaces the stage");
            render("grid");
        },
        () => {
            content.toggleGrid();
            root.kept = content.currentPath;
            Quickshell.execDetached(["cp", `${walls}/a.png`, `${walls}/paisajes/new.png`]);
        },
        () => CortetsuWallpapers.reload(),
        () => {
            verify(content.entries.length === 15, "a new file reaches the open manager");
            verify(content.currentPath === root.kept, "a rescan keeps the selection");
            content.apply();
        },
        () => verify(content.applying && content.currentStateLabel === "Aplicando", "applying is a visible state"),
        null, null, null, null,
        () => {
            verify(content.applyFailed && content.currentStateLabel === "No se pudo aplicar", "an unacknowledged apply fails");
            verify(content.currentPath === root.kept, "the failed candidate stays selected for a retry");
            render("failed");
        },
        () => content.requestMove(1),
        () => {
            verify(content.applyFailed && !content.currentFailed && content.currentStateLabel === "Vista previa", "the failure stays with the wallpaper that failed");
            verify(content.previewActive, "the next candidate is previewed");
            content.dismiss();
        },
        () => {
            verify(!retained.wallpaperManager && !CortetsuWallpapers.showPreview, "a click outside restores the wallpaper and closes");
            verify(CortetsuToaster.toasts.length === 1 && CortetsuToaster.toasts[0].title === "Vista previa descartada", "discarding a preview is announced");
        }
    ]

    readonly property var empty: [
        () => content.openManager(),
        () => {
            verify(content.libraryEmpty && !CortetsuWallpapers.scanning, "an empty folder is an explicit state");
            verify(content.presentationReady, "the empty state is presented");
            verify(content.currentPath === "" && content.orbitEntries.length === 0, "nothing is selected in an empty library");
            render("empty");
        }
    ]

    Timer {
        interval: 600; repeat: true; running: true
        onTriggered: {
            const steps = root.emptyRun ? root.empty : root.populated;
            if (root.step < steps.length) {
                const action = steps[root.step++];
                if (action)
                    action();
                return;
            }
            console.log("ORBITAL_RUNTIME_PASS", root.checks);
            Qt.quit();
        }
    }
}
"""


def png(path: Path, red: int, green: int, blue: int) -> None:
    """Write a 320x180 diagonal gradient so every tile is recognisable."""
    width, height = 320, 180
    rows = bytearray()
    for y in range(height):
        rows.append(0)
        for x in range(width):
            shade = (x + y) / (width + height)
            rows += bytes((int(red * (1 - shade * 0.7)), int(green * (0.4 + shade * 0.6)), int(blue * (1 - shade * 0.4))))

    def chunk(kind: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))

    path.write_bytes(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
                     + chunk(b"IDAT", zlib.compress(bytes(rows))) + chunk(b"IEND", b""))


def run(folder: Path, walls: Path, empty: bool) -> str:
    fake_bin = folder / "bin"
    fake_bin.mkdir(exist_ok=True)
    helper = fake_bin / "cortetsu-wallpaper-select"
    helper.write_text("#!/bin/sh\nexit 0\n")
    helper.chmod(0o755)
    result = subprocess.run(
        ["quickshell", "-p", str(folder / "shell.qml")],
        env={**os.environ, "QT_QPA_PLATFORM": os.environ.get("CORTETSU_TEST_QPA", "offscreen"), "CORTETSU_WALLPAPERS_DIR": str(walls),
             "XDG_STATE_HOME": str(folder / "state"), "PATH": f"{fake_bin}:{os.environ['PATH']}",
             "ORBITAL_EMPTY": "1" if empty else "0", "CORTETSU_RENDER_DIR": RENDER_DIR},
        capture_output=True, text=True, timeout=60,
    )
    output = result.stdout + result.stderr
    assert result.returncode == 0, output
    for marker in ("ORBITAL_FAIL", "TypeError", "ReferenceError", "is not a type", "Unable to assign"):
        assert marker not in output, output
    return output


with tempfile.TemporaryDirectory(prefix="cortetsu-wallpaper-orbital-") as temporary:
    folder = Path(temporary)
    walls = folder / "walls"
    for index in range(8):
        (walls / "paisajes").mkdir(parents=True, exist_ok=True)
        png(walls / "paisajes" / f"p{index}.png", 40 + index * 26, 150, 210 - index * 20)
    for index in range(4):
        (walls / "noche").mkdir(parents=True, exist_ok=True)
        png(walls / "noche" / f"n{index}.png", 90 + index * 30, 60, 160 + index * 20)
    png(walls / "a.png", 220, 150, 60)
    png(walls / "b.png", 200, 90, 90)
    empty_walls = folder / "empty"
    empty_walls.mkdir()

    for name in ("modules", "components", "services", "theme", "assets"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "modules/CortetsuConfig.qml").write_text(CONFIG)
    (folder / "modules/CortetsuIdleInhibitor.qml").write_text(IDLE_INHIBITOR)
    (folder / "modules/settings/SettingsController.qml").write_text(SETTINGS)
    (folder / "services/CortetsuColours.qml").write_text(COLOURS)
    (folder / "shell.qml").write_text(SHELL)
    state = folder / "state/cortetsu/wallpaper"
    state.mkdir(parents=True)
    (state / "path.txt").write_text(f"{walls}/paisajes/p3.png\n")

    assert "ORBITAL_RUNTIME_PASS 26" in run(folder, walls, empty=False)
    assert "ORBITAL_RUNTIME_PASS 3" in run(folder, empty_walls, empty=True)

print("PASS: the Wallpaper Orbital browses, filters, previews, keeps its selection and reports every state")
