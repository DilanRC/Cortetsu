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
source = source.replace('interval: 2000', 'interval: 25')
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
        property bool pairable: false
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
        verify(backend.pairDevice(backend.fakeDevice), "dispatch");
        verify(backend.busy, "must wait for state");
        verify(!backend.connectDevice(backend.fakeDevice), "single flight");
        backend.fakeDevice.paired = true;
        backend.checkCompletion();
        verify(backend.operation.state === "succeeded", "confirmed pairing");
        backend.fakeDevice.paired = false;
        backend.setScanOwner("a", true);
        backend.setScanOwner("b", true);
        backend.setScanOwner("a", false);
        verify(backend.fakeAdapter.discovering, "second owner retains scan");
        backend.setScanOwner("b", false);
        verify(!backend.fakeAdapter.discovering, "last owner releases scan");
        backend.pairDevice(backend.fakeDevice);
        verify(backend.busy, "pair pending");
        verify(backend.fakeAdapter.pairable, "pairing makes the adapter pairable so BlueZ stores the bond");
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
fake_busctl = """#!/usr/bin/env python3
import os, sys, time
from pathlib import Path
state = Path(__file__).with_name("power")
calls = Path(__file__).with_name("calls")
args = sys.argv[1:]
with calls.open("a") as log: log.write(" ".join(args) + "\\n")
lines = calls.read_text().splitlines()
on = state.read_text() == "on"
if "set-property" in args:
    state.write_text("on" if args[-1] == "true" else "off")
elif args[-1] == "Connect":
    if os.environ.get("BT_FAKE_CONNECT") == "hang": time.sleep(3)
    # BlueZ refuses the first attempt and accepts the next one.
    elif sum(line.endswith(" Connect") for line in lines) == 1: sys.exit("Call failed: Host is down")
elif args[-1] == "PowerState":
    # The first read lands while BlueZ is still powering the adapter up.
    print('s "off-enabling"' if len(lines) == 1 else 's "on"' if on else 's "off"')
elif args[-1] == "WakeAllowed":
    sys.exit("Unknown property")
elif args[-1] == "Powered":
    print("b true" if on else "b false")
"""

def scenario(qml, backend=source, **extra):
    """Run one shell against the backend with a fake busctl; return its output, the busctl calls and the final power."""
    with tempfile.TemporaryDirectory(prefix='cortetsu-bt-test-') as folder:
        folder = Path(folder)
        (folder / 'ConnectivityBluetooth.qml').write_text(backend)
        (folder / 'BluetoothPolicy.js').write_text((repo / 'cortetsu/services/BluetoothPolicy.js').read_text())
        (folder / 'shell.qml').write_text(qml)
        (folder / 'bin').mkdir()
        (folder / 'bin/busctl').write_text(fake_busctl)
        (folder / 'bin/busctl').chmod(0o700)
        (folder / 'bin/power').write_text('on')
        (folder / 'bin/calls').write_text('')
        env = {**os.environ, 'QT_QPA_PLATFORM': 'offscreen', 'PATH': f"{folder / 'bin'}:{os.environ['PATH']}", **extra}
        result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml')], env=env, capture_output=True, text=True, timeout=10)
        output = result.stdout + result.stderr
        print(output)
        assert result.returncode == 0 and 'BT_FAIL' not in output and 'Binding loop' not in output
        assert 'TypeError' not in output and 'ReferenceError' not in output and ' ERROR:' not in output
        return output, (folder / 'bin/calls').read_text(), (folder / 'bin/power').read_text()

output, _, _ = scenario(qml, BT_FAKE_CONNECT='hang')
assert 'BT_RUNTIME_PASS 18' in output, 'QML runtime lifecycle failed'

# Stale native power after an adapter re-registration: BlueZ is the authority for reads and writes.
stale_qml = """import QtQuick
import Quickshell
import "."
ShellRoot {
    property var backend: ConnectivityBluetooth
    property int checks: 0
    function verify(value, reason) { if (!value) { console.log("BT_FAIL", reason); return; } checks++; }
    Component.onCompleted: {
        backend.fakeAdapter.enabled = false;
        backend.adapters = [];
        backend.adapters = [backend.fakeAdapter];
        verify(!backend.enabled, "native value is used until BlueZ answers");
    }
    Timer { interval: 400; running: true; onTriggered: {
        verify(backend.enabled, "settled BlueZ power overrides the stale native value");
        verify(!backend.fakeAdapter.enabled, "native value stays stale in this scenario");
        verify(backend.setWakeAllowed(backend.fakeDevice, true), "wake dispatches");
    } }
    Timer { interval: 480; running: true; onTriggered: {
        verify(backend.operation.state === "failed" && backend.operation.lastErrorCode === "unsupported", "a device without WakeAllowed fails as unsupported, not by deadline");
        verify(!backend.propertyValue(backend.fakeDevice, "wakeAllowed"), "unsupported wake keeps the confirmed value");
        verify(backend.setEnabled(false), "power off dispatches");
    } }
    Timer { interval: 900; running: true; onTriggered: {
        verify(backend.operation.state === "succeeded", "power off confirmed although the native write was a no-op");
        verify(!backend.enabled, "confirmed power follows BlueZ");
        console.log("BT_STALE_PASS", checks);
        Qt.quit();
    } }
}
"""
output, calls, power = scenario(stale_qml)
assert 'BT_STALE_PASS 9' in output, 'stale native power was not reconciled'
assert 'set-property org.bluez /test/adapter org.bluez.Adapter1 Powered b false' in calls
assert power == 'off'

# Connect is confirmed by BlueZ's reply to Connect, never by the link coming up.
connect_qml = """import QtQuick
import Quickshell
import "."
ShellRoot {
    property var backend: ConnectivityBluetooth
    property int checks: 0
    function verify(value, reason) { if (!value) { console.log("BT_FAIL", reason); return; } checks++; }
    Component.onCompleted: {
        verify(backend.connectDevice(backend.fakeDevice), "connect dispatches");
        backend.fakeDevice.connected = true;
        backend.checkCompletion();
        verify(backend.busy, "a link that is up does not confirm the connection");
    }
    Timer { interval: 500; running: true; onTriggered: {
        verify(backend.operation.state === "failed" && backend.operation.lastErrorCode === "connect-failed", "a refusal from BlueZ fails the connection");
        verify(backend.operation.lastError.includes("Host is down") && !backend.operation.lastError.includes("exit="), "the failure carries BlueZ's reason");
        verify(backend.connectDevice(backend.fakeDevice), "retry dispatches");
    } }
    Timer { interval: 1000; running: true; onTriggered: {
        verify(backend.operation.state === "succeeded", "BlueZ's reply confirms the connection");
        console.log("BT_CONNECT_PASS", checks);
        Qt.quit();
    } }
}
"""
output, calls, _ = scenario(connect_qml, source.replace('deadline.interval = 100;', 'deadline.interval = 3000;'))
assert 'BT_CONNECT_PASS 6' in output, 'connect was not confirmed by the BlueZ reply'
assert calls.count('call org.bluez /test/device org.bluez.Device1 Connect') == 2
