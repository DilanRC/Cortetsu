#!/usr/bin/env python3
"""The real Calendar surface works from the keyboard.

Content.qml, CalendarService and CalendarModel run in Quickshell on the
offscreen platform with HOME, cache and config in a temporary tree and a
scripted `cortetsu-calendar` helper that only records its arguments. Keys are
real key events (QtTest TestEvent), so the check covers focus and event
propagation, not only the date arithmetic.

Before 2026-10-23 the surface had no key handling at all: a day could only be
chosen and a calendar only toggled with the pointer.

Set CORTETSU_RENDER_DIR to keep a PNG of the surface.
"""
import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / "cortetsu"
RENDER_DIR = os.environ.get("CORTETSU_RENDER_DIR", "")

SHELL = """import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import Quickshell.Io
import "modules/calendar" as Calendar
import "theme"

ShellRoot {
    id: root
    property int checks: 0
    property int step: 0
    property bool busy: false
    readonly property string renderDir: Quickshell.env("CORTETSU_RENDER_DIR")
    function verify(value, reason) { if (!value) console.log("CALENDAR_FAIL", reason); else checks++; }
    function day(date) { return Qt.formatDate(date, "yyyy-MM-dd"); }
    function find(item, test) {
        if (!item) return null;
        if (test(item)) return item;
        for (const child of item.children) { const hit = find(child, test); if (hit) return hit; }
        return null;
    }

    QtObject { id: retained; property bool calendar: true; function setRetained(name, value) { calendar = value; } }
    QtObject { id: screenState; property var cortetsuState: retained }

    Window {
        id: window
        width: 900; height: 660; visible: true; color: "#0B0D10"
        Calendar.Content { id: content; anchors.fill: parent; screenState: screenState }
    }
    TestEvent { id: events }

    readonly property var steps: [
        () => Calendar.CalendarService.calendars.length === 2,
        () => {
            content.selectedDate = new Date(2026, 9, 31);
            content.forceActiveFocus();
            events.keyClick(Qt.Key_Right, Qt.NoModifier, -1);
            verify(day(content.selectedDate) === "2026-11-01", `Right crosses into November (${day(content.selectedDate)})`);
            events.keyClick(Qt.Key_Up, Qt.NoModifier, -1);
            verify(day(content.selectedDate) === "2026-10-25", "Up goes back a week");
            events.keyClick(Qt.Key_PageDown, Qt.NoModifier, -1);
            verify(day(content.selectedDate) === "2026-11-25", "PageDown keeps the day");
            events.keyClick(Qt.Key_Left, Qt.ControlModifier, -1);
            verify(day(content.selectedDate) === "2026-11-25", "a chord is not a calendar move");
            events.keyClick(Qt.Key_Home, Qt.NoModifier, -1);
            verify(day(content.selectedDate) === day(new Date()), "Home returns to today");
            return true;
        },
        () => {
            // Tab from the surface reaches the calendar chips in order.
            const chips = [];
            let item = content;
            for (let i = 0; i < 30; ++i) {
                item = item.nextItemInFocusChain(true);
                if (item?.Accessible?.role === Accessible.CheckBox && !chips.includes(item)) chips.push(item);
            }
            verify(chips.length === 2, `both calendars are in the Tab order (${chips.length})`);
            verify(chips[0].Accessible.name === "Personal" && chips[0].Accessible.checked, "the chip names its calendar and state");
            chips[1].forceActiveFocus();
            verify(chips[1].border.width > 0 && Qt.colorEqual(chips[1].border.color, CortetsuDesign.colorIndicator) && chips[0].border.width === 0, "the focused chip shows a ring");
            events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
            // Arrows on a chip still move the day: the surface owns them.
            content.selectedDate = new Date(2026, 9, 10);
            events.keyClick(Qt.Key_Right, Qt.NoModifier, -1);
            verify(day(content.selectedDate) === "2026-10-11", "arrows work with a chip focused");
            // Qt.formatDate printed "Sunday, October 11" under a Spanish LANG.
            const title = find(content, item => item.objectName === "agendaTitle")?.text;
            verify(title === "Domingo, 11 de octubre", `the agenda date is Spanish (${title})`);
            return true;
        },
        () => {
            const log = calls.text();
            return log.includes("set-selection");
        },
        () => {
            verify(calls.text().includes("set-selection deportes true"), `Space toggles the focused calendar (${calls.text()})`);
            if (renderDir) content.grabToImage(result => result.saveToFile(`${renderDir}/calendar.png`));
            return true;
        },
        () => {
            // Today and the selected day must not look alike. `today` is pinned
            // so the check does not depend on the date the test runs.
            content.today = new Date(2026, 9, 23);
            content.selectedDate = new Date(2026, 9, 11);
            const today = find(content, item => item.objectName === "day-23");
            const selected = find(content, item => item.objectName === "day-11");
            verify(selected.border.width === 0 && today.border.width > 0, "today is a ring, the selected day a fill");
            return true;
        }
    ]

    FileView { id: calls; path: Quickshell.env("HOME") + "/calls.log"; watchChanges: true; onFileChanged: reload() }

    property int waitedMs: 0
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (root.busy) return;
            if (root.step >= root.steps.length) { console.log("CALENDAR_RUNTIME_PASS", root.checks); Qt.quit(); return; }
            root.busy = true;
            root.waitedMs += interval;
            calls.reload();
            try {
                if (root.steps[root.step]()) { root.step += 1; root.waitedMs = 0; }
                else if (root.waitedMs > 10000) { console.log("CALENDAR_FAIL", `step ${root.step} never became ready`); Qt.quit(); }
            } catch (error) {
                console.log("CALENDAR_FAIL", `step ${root.step}: ${error}`);
                Qt.quit();
            } finally {
                root.busy = false;
            }
        }
    }
}
"""

HELPER = """#!/bin/sh
echo "$*" >> "$HOME/calls.log"
"""

with tempfile.TemporaryDirectory(prefix="cortetsu-calendar-keys-") as temporary:
    folder = Path(temporary)
    for name in ("modules", "components", "services", "theme", "assets", "utils"):
        shutil.copytree(ROOT / name, folder / name)
    (folder / "shell.qml").write_text(SHELL)
    home = folder / "home"
    (home / ".local/bin").mkdir(parents=True)
    helper = home / ".local/bin/cortetsu-calendar"
    helper.write_text(HELPER)
    helper.chmod(0o755)
    (home / "calls.log").write_text("")
    (home / ".cache/cortetsu").mkdir(parents=True)
    (home / ".cache/cortetsu/calendar-events.json").write_text(json.dumps({
        "events": [],
        "calendars": [
            {"calendarId": "personal", "calendarName": "dilan", "primary": True, "calendarColor": "#4f8cff"},
            {"calendarId": "deportes", "calendarName": "Deportes", "primary": False, "calendarColor": "#36b37e"},
        ],
    }))
    (home / ".config/cortetsu").mkdir(parents=True)
    (home / ".config/cortetsu/calendar-selection.json").write_text(json.dumps({"enabled": ["personal"]}))
    env = {**os.environ, "LANG": "es_MX.UTF-8", "LC_TIME": "es_CR.UTF-8", "LC_ALL": "", "QT_QPA_PLATFORM": "offscreen", "HOME": str(home), "XDG_CACHE_HOME": str(home / ".cache"),
           "XDG_CONFIG_HOME": str(home / ".config"), "XDG_STATE_HOME": str(home / ".local/state"),
           "CORTETSU_RENDER_DIR": RENDER_DIR}
    env.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(["quickshell", "-p", str(folder / "shell.qml")], env=env,
                            capture_output=True, text=True, timeout=90)
    output = result.stdout + result.stderr
    assert "CALENDAR_RUNTIME_PASS 12" in output, output
    for marker in ("CALENDAR_FAIL", "TypeError", "ReferenceError", "Binding loop", "Unable to assign", "is not a type"):
        assert marker not in output, output

print("PASS: the Calendar moves the day with arrows, PageUp/PageDown and Home, and its calendars toggle from the keyboard")
