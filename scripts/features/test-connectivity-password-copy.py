"""Verify password copy and cancellation with a fake clipboard and nmcli."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='cortetsu-password-copy-') as temporary:
    folder = Path(temporary)
    for name in ('ConnectivityWifi.qml', 'ConnectivityNmAdapter.qml', 'ConnectivityPolicy.js', 'CortetsuSettingsNetwork.qml'):
        shutil.copy(repo / 'cortetsu/services' / name, folder / name)
    facade = folder / 'CortetsuSettingsNetwork.qml'
    source = facade.read_text()
    assert 'Quickshell.clipboardText = secret' in source
    facade.write_text(source.replace('id: root', 'id: root\n    property string testClipboard: ""', 1)
                            .replace('Quickshell.clipboardText = secret', 'root.testClipboard = secret'))
    binary = folder / 'nmcli'
    binary.write_text('''#!/usr/bin/env python3
import sys, time
args = sys.argv[1:]
assert 'fixture-copy-secret' not in ' '.join(args)
if args == ['monitor']:
    while True: time.sleep(60)
elif '--show-secrets' in args:
    assert args[-2] == 'uuid'
    if args[-1].endswith('013'): time.sleep(2)
    if args[-1].endswith('014'): sys.exit(1)
    print('fixture-copy-secret')
elif 'radio' in args: print('enabled')
elif 'UUID,NAME,TYPE,AUTOCONNECT,DEVICE' in args:
    for suffix in ('012', '013', '014'):
        print('12345678-abcd-1234-abcd-123456789' + suffix + ':Different profile name:802-11-wireless:yes:')
elif 'uuid' in args: print('802-11-wireless.ssid:Fixture\\nconnection.interface-name:wlan0')
''')
    binary.chmod(0o700)
    (folder / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int stage: 0
    readonly property var copy: CortetsuSettingsNetwork
    Component.onCompleted: console.log("COPY_STARTED", copy.state)
    function check(value, message) {
        if (!value) { console.error("COPY_FAIL", message); Qt.quit(); }
        return value;
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0) {
                if (copy.profiles.length !== 3) return;
                copy.copyPassword("--help");
                if (!root.check(!copy.secretBusy, "invalid UUID launched query")) return;
                copy.copyPassword("12345678-abcd-1234-abcd-123456789012");
                if (!root.check(copy.secretBusy, "copy not pending")) return;
                root.stage = 1;
            } else if (root.stage === 1) {
                if (copy.secretState !== "ready") return;
                if (!root.check(copy.testClipboard === "fixture-copy-secret" && !copy.secretBusy && copy.passwordCopyProcess === null, "success did not copy or release process")) return;
                copy.testClipboard = "untouched";
                copy.copyPassword("12345678-abcd-1234-abcd-123456789013");
                copy.cancelPasswordCopy();
                if (!root.check(!copy.secretBusy && copy.secretState === "idle" && copy.testClipboard === "untouched", "cancel retained process or changed clipboard")) return;
                copy.copyPassword("12345678-abcd-1234-abcd-123456789014");
                root.stage = 2;
            } else {
                if (copy.secretState !== "error") return;
                if (!root.check(!copy.secretBusy && copy.passwordCopyProcess === null && copy.testClipboard === "untouched", "failed query changed clipboard or retained collector")) return;
                console.log("COPY_FIXTURE_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 6000; running: true; onTriggered: { console.error("COPY_FAIL", "deadline"); Qt.quit(); } }
}
''')
    env = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}", QT_QPA_PLATFORM='offscreen')
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml'), '--no-color'], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=9)
    assert result.returncode == 0 and 'COPY_FIXTURE_PASS' in result.stdout and 'COPY_FAIL' not in result.stdout, result.stdout
    assert 'fixture-copy-secret' not in result.stdout and ' WARN' not in result.stdout, result.stdout
    processes = subprocess.run(['ps', '-eo', 'args'], text=True, stdout=subprocess.PIPE, check=True).stdout
    assert str(binary) not in processes, 'password query or monitor survived shell exit'
print('PASS: password copy uses UUID, verifies success, cancels safely and destroys collectors without touching the real clipboard')
