#!/usr/bin/env python3
"""Quick Settings with service doubles: every tile either acts or is a reading.

The Wi-Fi tile used to be `clickable: false`: it looked like a switch and did
nothing. Here it toggles the radio through the same service Settings uses,
waits for the radio's answer instead of jumping ahead, says why a change was
refused, and falls back to a reading when there is nothing to operate. The
microphone tile mutes the default source and disappears as a control when
there is no source.

    test-cortetsu-quick-settings-runtime.py     (set CORTETSU_RENDER_DIR for PNGs)
"""
import tempfile
from pathlib import Path

from settings_harness import build_tree, run

SHELL = r"""import QtQuick
import QtTest
import Quickshell
import "modules"
import "modules/osd" as Osd
import "components"
import "services"
import "theme"

ShellRoot {
    id: root
    readonly property string out: Quickshell.env("CORTETSU_RENDER_DIR")
    property int step: 0
    property int checks: 0
    property int waited: 0
    property bool grabbing: false
    readonly property var wifi: ConnectivityWifi
    readonly property var palette: CortetsuColours

    function verify(value, reason) { if (!value) console.log("SETTINGS_FAIL", reason); else checks++; }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const kid of item.children ?? []) { const hit = find(kid, name); if (hit) return hit; }
        return null;
    }
    function grab(name) {
        if (!out) return;
        grabbing = true;
        window.contentItem.grabToImage(r => { r.saveToFile(`${out}/quick-settings-${name}.png`); root.grabbing = false; });
    }

    QtObject { id: screenDouble; property bool osd: true; property bool settings: false }
    TestEvent { id: events }

    Window {
        id: window
        width: 600; height: 760; visible: true
        color: CortetsuDesign.colorSumi

        CortetsuPopupSurface {
            x: 20; y: 20; width: 560; height: panel.implicitHeight + 40
            Osd.FullContent {
                id: panel
                x: 20; y: 20; width: 520
                screenState: screenDouble
                screen: Quickshell.screens[0]
            }
        }
    }

    readonly property var steps: [
        () => CortetsuConfig.loaded && window.active && panel.height > 0,
        () => {
            const tile = find(panel, "quickWifi");
            verify(tile.clickable && tile.label === "Casa", `the Wi-Fi tile names the network and can be pressed (${tile.label})`);
            verify(panel.height < 700, `the panel is as tall as its content (${panel.height})`);
            grab("default");
            tile.forceActiveFocus();
            events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            return true;
        },
        () => wifi.busy && !grabbing,
        () => {
            const tile = find(panel, "quickWifi");
            verify(wifi.operation.id === 1 && wifi.pendingEnabled === false, "Enter asks the radio to turn off");
            verify(tile.detail === "Aplicando…" && tile.label === "Casa", "the tile waits for the radio instead of jumping ahead");
            events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            verify(wifi.operation.id === 1, "a second press while busy starts nothing");
            wifi.settle(false);
            return true;
        },
        () => !wifi.busy,
        () => {
            const tile = find(panel, "quickWifi");
            verify(wifi.wifiEnabled && tile.detail === "NetworkManager rechazó el cambio", `a refused change says why (${tile.detail})`);
            events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            wifi.settle(true);
            return true;
        },
        () => !wifi.busy && !wifi.wifiEnabled,
        () => {
            const tile = find(panel, "quickWifi");
            verify(tile.label === "Wi-Fi apagado" && tile.detail === "Pulsa para encenderlo" && !tile.warning,
                `off by choice is a state, not a fault (${tile.label} / ${tile.detail})`);
            grab("wifi-off");
            wifi.hardwareEnabled = false;
            return true;
        },
        () => !grabbing,
        () => {
            const tile = find(panel, "quickWifi");
            verify(!tile.clickable && tile.detail === "Bloqueado por el interruptor del equipo",
                "a radio blocked by its switch is a reading with nothing to press");
            wifi.hardwareEnabled = true; wifi.wifiEnabled = true;
            const mic = find(panel, "quickMicrophone");
            verify(mic.clickable && mic.label === "Micrófono" && mic.detail === "Micrófono interno", `the microphone tile names the input (${mic.detail})`);
            mic.forceActiveFocus();
            events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
            verify(CortetsuAudio.sourceMuted && mic.label === "Micrófono silenciado" && !mic.warning,
                "Space mutes the default source and the tile says so");
            events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
            verify(!CortetsuAudio.sourceMuted, "and unmutes it again");
            CortetsuAudio.available = false;
            return true;
        },
        () => {
            const mic = find(panel, "quickMicrophone");
            verify(!mic.clickable && mic.label === "Sin micrófono", "without an input the tile is a reading, not a dead switch");
            // It was the focus item when the input went away: keys reach it
            // and must do nothing.
            events.keyClick(Qt.Key_Space, Qt.NoModifier, -1);
            events.keyClick(Qt.Key_Return, Qt.NoModifier, -1);
            verify(!mic.enabled && !mic.activeFocus, "a reading is disabled, so no key or Tab reaches it");
            verify(find(panel, "quickEnergy").text.length > 0, "energy keeps its one line");
            grab("no-audio");
            return true;
        },
        () => !grabbing
    ]

    Timer {
        interval: 50; repeat: true; running: true
        onTriggered: {
            if (root.step >= root.steps.length) { console.log(`SETTINGS_RUNTIME_PASS ${root.checks}`); Qt.quit(); return; }
            try {
                if (root.steps[root.step]()) { root.step++; root.waited = 0; }
                else if (++root.waited > 200) { console.log("SETTINGS_FAIL", `step ${root.step} never became ready`); Qt.quit(); }
            } catch (error) { console.log("SETTINGS_FAIL", `step ${root.step} threw: ${error}`); Qt.quit(); }
        }
    }
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix="cortetsu-quick-") as temporary:
        folder = Path(temporary)
        build_tree(folder)
        (folder / "quick.qml").write_text(SHELL, encoding="utf-8")
        output, _ = run(folder, "quick.qml", "quick", preferences={"schema": 1})
        failures = [line for line in output.splitlines() if "SETTINGS_FAIL" in line]
        assert not failures and "SETTINGS_RUNTIME_PASS 14" in output, failures or output[-3000:]
    print("PASS: Quick Settings toggles Wi-Fi through its service, waits for the radio, reports a refusal, "
          "mutes the microphone, and turns into readings when there is nothing to operate")


if __name__ == "__main__":
    main()
