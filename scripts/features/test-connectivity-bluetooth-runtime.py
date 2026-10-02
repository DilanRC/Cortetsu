#!/usr/bin/env python3
"""Exercise the actual QML backend with fake native objects; never touch hardware."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'cortetsu/services/ConnectivityBluetooth.qml').read_text()
source = source.replace('readonly property var adapters: Bluetooth.adapters.values', 'property var adapters: [fakeAdapter]')
source = source.replace('readonly property var allDevices: Bluetooth.devices.values', 'property var allDevices: [fakeDevice]')
source = source.replace('Bluetooth.defaultAdapter', 'fakeAdapter')
source = source.replace('property BluetoothAdapter', 'property var')
source = source.replace('interval: 500', 'interval: 25')
source = source.replace('kind === "pair" ? 60000 : 20000', '100')
source = source.replace('    id: root', '''    id: root
    property QtObject fakeDevice: QtObject {
        property string dbusPath: "/test/device"
        property bool connected: false
        property bool paired: false
        property bool bonded: false
        property bool pairing: false
        property bool trusted: false
        property bool blocked: false
        property bool wakeAllowed: false
        function connect() {}
        function disconnect() {}
        function pair() { pairing = true; }
        function cancelPair() { pairing = false; }
        function forget() {}
    }
    property QtObject fakeAdapter: QtObject {
        property string dbusPath: "/test/adapter"
        property bool enabled: true
        property bool discovering: false
        property int state: 1
        property QtObject devices: QtObject { property var values: [root.fakeDevice] }
    }''', 1)
qml = '''import QtQuick
import Quickshell
import "."
ShellRoot {
    property var backend: ConnectivityBluetooth
    property int checks: 0
    function verify(value, reason) { if (!value) { console.log("BT_FAIL", reason); return; } checks++; }
    Component.onCompleted: {
        verify(backend.connectDevice(backend.fakeDevice), "dispatch");
        verify(backend.busy, "must wait for state");
        verify(!backend.connectDevice(backend.fakeDevice), "single flight");
        backend.fakeDevice.connected = true;
        backend.checkCompletion();
        verify(backend.operation.state === "succeeded", "confirmed connection");
        backend.setScanOwner("a", true);
        backend.setScanOwner("b", true);
        backend.setScanOwner("a", false);
        verify(backend.fakeAdapter.discovering, "second owner retains scan");
        backend.setScanOwner("b", false);
        verify(!backend.fakeAdapter.discovering, "last owner releases scan");
        backend.pairDevice(backend.fakeDevice);
        verify(backend.busy, "pair pending");
        backend.cancelPair();
        backend.checkCompletion();
        verify(!backend.fakeDevice.pairing && !backend.busy, "cancel confirmed");
        backend.forgetDevice(backend.fakeDevice);
        verify(!backend.selectAdapter(backend.fakeAdapter), "cannot switch adapter during operation");
        backend.adapters = [];
        backend.checkCompletion();
        verify(backend.operation.state === "failed" && backend.operation.lastErrorCode === "adapter-removed", "adapter removal cannot confirm forget");
        backend.adapters = [backend.fakeAdapter];
        backend.fakeDevice.connected = false;
        backend.setTrusted(backend.fakeDevice, true);
        verify(backend.busy && backend.fakeDevice.trusted, "optimistic setter must await DBus readback");
        verify(!backend.propertyValue(backend.fakeDevice, "trusted"), "UI retains confirmed trust while pending");
    }
    Timer { interval: 250; running: true; onTriggered: {
        verify(backend.operation.state === "failed", "deadline fails unconfirmed property write");
        verify(backend.operation.lastErrorCode === "timeout", "timeout code");
        verify(!backend.propertyValue(backend.fakeDevice, "trusted"), "rejected property keeps confirmed value");
        backend.allDevices = [];
        verify(Object.keys(backend.confirmedProperties).length === 0, "removed device drops confirmed cache before same-path reuse");
        backend.allDevices = [backend.fakeDevice];
        backend.connectDevice(backend.fakeDevice);
    } }
    Timer { interval: 500; running: true; onTriggered: {
        verify(backend.operation.state === "failed", "connection deadline");
        console.log("BT_RUNTIME_PASS", checks);
        Qt.quit();
    } }
}
'''
with tempfile.TemporaryDirectory(prefix='cortetsu-bt-test-') as folder:
    folder = Path(folder)
    (folder / 'ConnectivityBluetooth.qml').write_text(source)
    (folder / 'BluetoothPolicy.js').write_text((repo / 'cortetsu/services/BluetoothPolicy.js').read_text())
    (folder / 'shell.qml').write_text(qml)
    result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml')], env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}, capture_output=True, text=True, timeout=5)
    output = result.stdout + result.stderr
    print(output)
    assert result.returncode == 0 and 'BT_RUNTIME_PASS 17' in output, 'QML runtime lifecycle failed'
    assert 'BT_FAIL' not in output and 'Binding loop' not in output
    assert 'TypeError' not in output and 'ReferenceError' not in output and ' ERROR:' not in output
