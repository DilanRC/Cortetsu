#!/usr/bin/env python3
"""The Hub's service popouts with service doubles: level 1 of each service.

Network: the radio switch acts through ConnectivityWifi and waits for it.
Bluetooth: one header line with the adapter switch; a device shows its
battery only when BlueZ reports one. Audio: the input (microphone) beside the
output. Every popout leads to its Settings page and closes on the way.

    test-cortetsu-service-popouts-runtime.py   (set CORTETSU_RENDER_DIR for PNGs)
"""
import tempfile
from pathlib import Path

from settings_harness import build_tree, run

SHELL = r"""import QtQuick
import QtTest
import Quickshell
import "modules"
import "modules/bar/popouts"
import "modules/settings"
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
    property int closes: 0
    readonly property var wifi: ConnectivityWifi
    readonly property var bluetooth: ConnectivityBluetooth
    readonly property var palette: CortetsuColours

    function verify(value, reason) { if (!value) console.log("SETTINGS_FAIL", reason); else checks++; }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (const kid of item.children ?? []) { const hit = find(kid, name); if (hit) return hit; }
        return null;
    }
    function texts(item) {
        const out = [];
        (function walk(node) {
            if (!node) return;
            if (node.visible !== false && typeof node.text === "string" && node.text.length) out.push(node.text);
            for (const kid of node.children ?? []) walk(kid);
        })(item);
        return out;
    }
    function grab(name) {
        if (!out) return;
        grabbing = true;
        window.contentItem.grabToImage(r => { r.saveToFile(`${out}/popouts-${name}.png`); root.grabbing = false; });
    }

    PopoutState { id: state; onCloseRequested: root.closes++ }
    TestEvent { id: events }

    Window {
        id: window
        width: 1140; height: 720; visible: true
        color: CortetsuDesign.colorSumi

        CortetsuNetworkPopup { id: network; x: 16; y: 16; width: 336; popouts: state }
        CortetsuBluetoothPopup { id: bt; x: 380; y: 16; width: 336; popouts: state }
        CortetsuAudioPopup { id: audio; x: 744; y: 16; width: 348; popouts: state }
    }

    readonly property var steps: [
        () => CortetsuConfig.loaded && window.active && network.height > 0,
        () => {
            const power = find(network, "popoutWifiPower");
            verify(power.visible && power.checked, "the network popout carries the Wi-Fi switch");
            verify(texts(network).includes("Wi-Fi encendido"), `the header says how the radio stands (${texts(network)})`);
            verify(!!find(network, "popoutSettings") && !!find(bt, "popoutSettings") && !!find(audio, "popoutSettings"),
                "every service popout leads to its Settings page");
            const btText = texts(bt);
            verify(btText.some(t => t.includes("batería 82 %")), `a device shows the battery BlueZ reports (${btText})`);
            verify(!btText.some(t => t.includes("Teclado") && t.includes("batería")), "and nothing for one that reports none");
            verify(btText.filter(t => t === "Bluetooth activado").length === 0, "the adapter is one header line, not a header and a card");
            verify(btText.includes("1 conectado") && texts(audio).includes("1 dispositivo"), "a count of one is singular");
            verify(texts(network).includes("No hay otras redes"), "connected with nothing else around is not 'no networks'");
            verify(!!find(audio, "popoutMicrophone") && find(audio, "popoutMicrophone").visible, "the audio popout shows the input");
            grab("default");
            find(network, "popoutWifiPower").toggled(false);
            return true;
        },
        () => wifi.busy && !grabbing,
        () => {
            verify(find(network, "popoutWifiPower").checked && texts(network).includes("Aplicando…"),
                "the switch waits for the radio and says so");
            wifi.settle(false);
            return true;
        },
        () => !wifi.busy,
        () => {
            verify(texts(network).includes("NetworkManager rechazó el cambio"), "a refused change is shown in the popout");
            bluetooth.enabled = false;
            return true;
        },
        () => {
            const btText = texts(bt);
            verify(btText.includes("Bluetooth está apagado") && btText.includes("Apagado"), `off is a state with its message (${btText})`);
            CortetsuAudio.available = false;
            return true;
        },
        () => {
            verify(!find(audio, "popoutMicrophone").visible && texts(audio).includes("Sin micrófono"),
                "without an input the popout says so instead of a dead slider");
            find(bt, "popoutSettings").clicked();
            return true;
        },
        () => {
            verify(SettingsController.selectedPage?.id === "bluetooth" || SettingsController.pageId === "bluetooth",
                `the link selects the Bluetooth page (${SettingsController.pageId})`);
            verify(root.closes === 1, "and closes the popout");
            grab("states");
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
    with tempfile.TemporaryDirectory(prefix="cortetsu-popouts-") as temporary:
        folder = Path(temporary)
        build_tree(folder)
        (folder / "popouts.qml").write_text(SHELL, encoding="utf-8")
        output, _ = run(folder, "popouts.qml", "popouts", preferences={"schema": 1})
        failures = [line for line in output.splitlines()
                    if "SETTINGS_FAIL" in line or "TypeError" in line or "ReferenceError" in line or "is not a type" in line]
        assert not failures and "SETTINGS_RUNTIME_PASS 15" in output, failures or output[-3000:]
    print("PASS: the network, Bluetooth and audio popouts act at level 1 through their services, "
          "show only reported values and lead to their Settings page")


if __name__ == "__main__":
    main()
