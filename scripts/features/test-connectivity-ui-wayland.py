#!/usr/bin/env python3
"""Opt-in visible UI checks against a built runtime; scans, never changes connections."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', required=True, type=Path)
parser.add_argument('--log', type=Path)
args = parser.parse_args()
assert os.environ.get('WAYLAND_DISPLAY'), 'This acceptance test requires the live Wayland session'
runtime = args.runtime.resolve()
assert (runtime / 'shell.qml').is_file()
with tempfile.TemporaryDirectory(prefix='cortetsu-connectivity-ui-') as temporary:
    folder = Path(temporary)
    for name in ('modules', 'components', 'services', 'utils', 'assets', 'base'):
        if (runtime / name).exists():
            (folder / name).symlink_to(runtime / name, target_is_directory=True)
    (folder / 'shell.qml').write_text('''import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import Quickshell
import qs.modules.settings as Settings
import qs.services
import qs.modules
ShellRoot {
    id: root
    property int page: 0
    property int stage: 0
    property int checks: 0
    function check(value, reason) { if (!value) { console.error("UI_FAIL", reason); Qt.quit(); return false; } checks++; return true; }
    function findLabel(item, label) {
        if (!item) return null;
        if (item.label === label) return item;
        for (const child of item.children ?? []) { const found = findLabel(child, label); if (found) return found; }
        return null;
    }
    FloatingWindow {
        id: window
        visible: true; implicitWidth: 1000; implicitHeight: 760
        title: "Cortetsu Connectivity acceptance"
        color: "#1c2027"
        ScrollView {
            anchors.fill: parent; contentWidth: availableWidth
            ColumnLayout {
                width: window.width - 32
                Loader { id: wifi; Layout.fillWidth: true; Layout.preferredHeight: item?.implicitHeight ?? 0; active: root.page===0; visible: active; sourceComponent: Settings.NetworkPage { screen:null; screenState:null } }
                Loader { id: bt; Layout.fillWidth: true; Layout.preferredHeight: item?.implicitHeight ?? 0; active: root.page===1; visible: active; sourceComponent: Settings.BluetoothPage { screen:null; screenState:null } }
            }
        }
        TestCase { id: input; when:false; optional:true }
    }
    Timer {
        interval: 800; running:true; repeat:true
        onTriggered: {
            if (root.stage === 0) {
                if (!wifi.item || !Connectivity.wifi.profiles.length) return;
                if (!root.check(CortetsuNetwork.activeWifiNetwork === Connectivity.wifi.activeNetwork, "bar and BottomHub native Wi-Fi identity")) return;
                if (!root.check(CortetsuSettingsNetwork.operation === Connectivity.wifi.operation, "Settings shared operation identity")) return;
                const properties = root.findLabel(wifi.item, "Propiedades");
                if (!root.check(!!properties, "connected properties action")) return;
                input.mouseClick(properties, properties.width/2, properties.height/2);
                if (!root.check(wifi.item.selectedNetwork === Connectivity.wifi.activeNetwork, "mouse selects native connected network")) return;
                input.keyClick(Qt.Key_Tab);
                if (!root.check(!!window.contentItem.Window.window.activeFocusItem, "Tab assigns focus")) return;
                const close = root.findLabel(wifi.item, "Cerrar detalle");
                input.mouseClick(close, close.width/2, close.height/2);
                if (!root.check(!wifi.item.selectedNetwork, "inspector closes")) return;
                const add = root.findLabel(wifi.item, "Añadir red");
                if (!root.check(!!add, "hidden network action")) return;
                add.forceActiveFocus(); input.keyClick(Qt.Key_Return);
                if (!root.check(!!root.findLabel(wifi.item, "Conectar red oculta"), "keyboard opens hidden form")) return;
                root.page = 1; root.stage = 1;
            } else if (root.stage === 1) {
                if (!bt.item) return;
                if (!root.check(!wifi.item && !Connectivity.wifi.scanning, "leaving Wi-Fi releases page and scanner")) return;
                if (!root.check(bt.item.bluetooth === Connectivity.bluetooth, "Bluetooth shared identity")) return;
                input.keyClick(Qt.Key_Tab);
                root.page = 2; root.stage = 2;
            } else {
                if (Connectivity.bluetooth.discovering) return;
                if (!root.check(!bt.item, "leaving Bluetooth releases page")) return;
                console.log("UI_WAYLAND_PASS", root.checks, "mouse/Tab/Return/native identity/page lifetime/scanner release");
                Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running:true; onTriggered: { console.error("UI_FAIL", "acceptance deadline"); Qt.quit(); } }
}
''')
    result = subprocess.run(['qs', '-p', str(folder), '-n'], capture_output=True, text=True, timeout=18)
    output = result.stdout + result.stderr
    if args.log:
        args.log.write_text(output)
    print(output)
    assert result.returncode == 0 and 'UI_WAYLAND_PASS' in output and 'UI_FAIL' not in output
    assert 'TypeError' not in output and 'ReferenceError' not in output and ' ERROR:' not in output
