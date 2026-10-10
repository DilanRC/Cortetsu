#!/usr/bin/env python3
"""Runtime check of the launcher application grid (SUPER).

The real AppList.qml and Apps.qml run inside Quickshell against a private set
of application directories, so Quickshell's own scanner and file watcher do
the work.

What it proves:
- the grid is ordered by name, whatever order Quickshell's hash gives;
- a rescan caused by an unrelated file in a parent directory removes no cell,
  keeps the cell of an entry that exists in two directories and leaves the
  selection where it was;
- an application installed while the grid is open appears in its place and the
  selection stays on the same application;
- a new query selects the first result;
- actions and the calculator row, which have no id, still fill the grid.
"""
import tempfile
from pathlib import Path

from settings_harness import build_tree, run

SHELL = r"""import QtQuick
import QtQuick.Controls
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "modules"
import "modules/launcher"
import "modules/launcher/services"

ShellRoot {
    id: root

    property int step: 0
    property int scans: 0
    property int scansBefore: 0
    property int lowestCount: -1
    property var steamCell: null
    property string selectedId: ""
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME")

    function fail(message: string): void {
        console.error(`LAUNCHER_APPS_FAIL step=${step} ${message}`);
        Qt.exit(1);
    }

    function check(condition: bool, message: string): void {
        if (!condition)
            fail(message);
    }

    function shown(): var {
        const result = [];
        for (let index = 0; index < list.count; index++)
            result.push(list.itemAtIndex(index)?.modelData ?? null);
        return result;
    }

    function cellFor(id: string): var {
        for (let index = 0; index < list.count; index++) {
            const cell = list.itemAtIndex(index);
            if (cell?.modelData?.id === id)
                return cell;
        }
        return null;
    }

    function checkOrder(expected: var): void {
        const entries = shown();
        check(entries.every(entry => entry !== null), "a cell has no application");
        const names = entries.map(entry => entry.name);
        const sorted = [...entries].sort((a, b) => a.name.localeCompare(b.name) || a.id.localeCompare(b.id));
        check(entries.every((entry, index) => entry === sorted[index]), `not ordered by name: ${names}`);
        check(JSON.stringify(entries.map(entry => entry.id)) === JSON.stringify(expected),
            `shows ${entries.map(entry => entry.id)}, expected ${expected}`);
    }

    QtObject {
        id: state
        property bool launcher: true
    }

    Connections {
        target: DesktopEntries
        function onApplicationsChanged(): void { root.scans++; }
    }

    Connections {
        target: list
        function onCountChanged(): void {
            if (root.lowestCount >= 0)
                root.lowestCount = Math.min(root.lowestCount, list.count);
        }
    }

    Process { id: touch; command: ["touch", `${root.dataHome}/recently-used.xbel`] }
    Process {
        id: install
        command: ["cp", Quickshell.env("LAUNCHER_NEW_APP"), `${root.dataHome}/applications/new-app.desktop`]
    }

    Window {
        width: 800
        height: 480
        visible: true

        TextField { id: search }

        // Below the pointer, which rests at the origin and selects what it hovers.
        AppList {
            id: list
            y: 48
            width: 760
            height: 432
            search: search
            screenState: state
        }
    }

    Timer { interval: 20000; running: true; onTriggered: root.fail("timed out") }

    // Each step waits for its condition, then checks and starts the next change.
    Timer {
        interval: 50
        repeat: true
        running: true
        onTriggered: {
            if (root.step === 0 && root.scans > 0 && list.count === 6 && root.cellFor("aa-last")) {
                root.checkOrder(["zz-first", "cc", "dd", "kk", "steam", "aa-last"]);
                root.check(list.currentIndex === 0, `the grid opened with ${list.currentIndex} selected`);
                list.currentIndex = 3;
                root.selectedId = list.currentItem.modelData.id;
                root.steamCell = root.cellFor("steam");
                root.lowestCount = list.count;
                root.scansBefore = root.scans;
                touch.running = true;
                root.step = 1;
            } else if (root.step === 1 && root.scans > root.scansBefore) {
                root.check(root.lowestCount === 6, `the grid dropped to ${root.lowestCount} applications during a rescan`);
                root.check(root.steamCell !== null && root.cellFor("steam") === root.steamCell,
                    "the cell of an application present in two directories was rebuilt");
                root.check(root.steamCell.modelData?.name === "Steam", "the kept cell lost its application");
                root.check(list.currentIndex === 3, `a rescan moved the selection to ${list.currentIndex}`);
                root.checkOrder(["zz-first", "cc", "dd", "kk", "steam", "aa-last"]);
                install.running = true;
                root.step = 2;
            } else if (root.step === 2 && list.count === 7 && root.cellFor("new-app")) {
                root.checkOrder(["new-app", "zz-first", "cc", "dd", "kk", "steam", "aa-last"]);
                root.check(list.currentItem?.modelData?.id === root.selectedId,
                    `the selection left ${root.selectedId} for ${list.currentItem?.modelData?.id} (index ${list.currentIndex}) when an application was installed`);
                list.currentIndex = 5;
                search.text = "st";
                root.step = 3;
            } else if (root.step === 3 && list.count === 1 && root.cellFor("steam")) {
                root.check(list.currentIndex === 0, "a new query did not select the first result");
                root.check(list.currentItem?.modelData?.id === "steam", "the query did not find Steam");
                search.text = CortetsuConfig.actionPrefix;
                root.step = 4;
            } else if (root.step === 4 && list.state === "actions" && list.count === 2 && list.itemAtIndex(1)) {
                // Actions have no id: the model compares them by identity, as before.
                root.check(list.count === Actions.query(search.text).length, `shows ${list.count} actions`);
                root.check(root.shown().every(action => action?.name), "an action cell has no action");
                search.text = `${CortetsuConfig.actionPrefix}calc `;
                root.step = 5;
            } else if (root.step === 5 && list.state === "calc" && list.count === 1 && list.itemAtIndex(0)) {
                root.check(list.itemAtIndex(0).modelData === 0, "the calculator row lost its value");
                console.log("LAUNCHER_APPS_PASS scans", root.scans);
                Qt.quit();
            }
        }
    }
}
"""

PREFERENCES = {"schema": 1, "hiddenApps": ["masked"], "actions": [
    {"name": "Apagar", "icon": "power_settings_new", "description": "Apaga el equipo", "command": ["true"]},
    {"name": "Bloquear", "icon": "lock", "description": "Bloquea la sesión", "command": ["true"]},
]}


def desktop(name: str, extra: str = "") -> str:
    return f"[Desktop Entry]\nType=Application\nName={name}\nExec=/bin/true\n{extra}"


with tempfile.TemporaryDirectory(prefix="cortetsu-launcher-apps-") as raw:
    folder = Path(raw)
    build_tree(folder)
    (folder / "launcher-apps.qml").write_text(SHELL, encoding="utf-8")

    system = folder / "xdg/system/applications"
    user = folder / "xdg/user/applications"
    system.mkdir(parents=True)
    user.mkdir(parents=True)
    # Ids and names sort in opposite directions, and two applications share a name.
    for app_id, name in (("zz-first", "Alfa"), ("cc", "Delta"), ("dd", "Delta"), ("kk", "Mango"),
                         ("steam", "Steam"), ("aa-last", "Zulu"), ("masked", "Kilo")):
        (system / f"{app_id}.desktop").write_text(desktop(name), encoding="utf-8")
    (system / "background.desktop").write_text(desktop("Oculta", "NoDisplay=true\n"), encoding="utf-8")
    # The user copy shadows the system one, as a Steam or browser shortcut does.
    (user / "steam.desktop").write_text(desktop("Steam"), encoding="utf-8")
    new_app = folder / "new-app.desktop"
    new_app.write_text(desktop("Aardvark"), encoding="utf-8")

    output, _ = run(folder, "launcher-apps.qml", "launcher-apps", preferences=PREFERENCES,
                    env={"XDG_DATA_HOME": str(user.parent), "XDG_DATA_DIRS": str(system.parent),
                         "LAUNCHER_NEW_APP": str(new_app)}, timeout=60)
    assert "LAUNCHER_APPS_PASS" in output, output

print("PASS: launcher application grid runtime")
