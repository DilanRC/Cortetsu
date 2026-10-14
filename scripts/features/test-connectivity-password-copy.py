"""Password copy: secret via stdin to a sensitive, expiring wl-copy; never argv or logs."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
SECRET = 'fixture-copy-secret'
with tempfile.TemporaryDirectory(prefix='cortetsu-password-copy-') as temporary:
    folder = Path(temporary)
    offers = folder / 'offers'
    offers.mkdir()
    for name in ('ConnectivityWifi.qml', 'ConnectivityNmAdapter.qml', 'ConnectivityPolicy.js', 'CortetsuSettingsNetwork.qml'):
        shutil.copy(repo / 'cortetsu/services' / name, folder / name)
    facade = folder / 'CortetsuSettingsNetwork.qml'
    source = facade.read_text()
    # The regression: a plain clipboard write lands in clipse's history.
    assert 'Quickshell.clipboardText' not in source.replace('// entry. Quickshell.clipboardText', '')
    assert 'readonly property int secretClipboardLifetime: 45000' in source
    facade.write_text(source.replace('secretClipboardLifetime: 45000', 'secretClipboardLifetime: 900'))
    nmcli = folder / 'nmcli'
    nmcli.write_text(f'''#!/usr/bin/env python3
import sys, time
args = sys.argv[1:]
assert 'fixture-' not in ' '.join(args)
if args == ['monitor']:
    while True: time.sleep(60)
elif '--show-secrets' in args:
    assert args[-2] == 'uuid'
    suffix = args[-1][-3:]
    if suffix == '013': time.sleep(2)
    if suffix == '014': sys.exit(1)
    print({{'012': '{SECRET}', '015': 'fixture-replaced-secret', '016': 'fixture-refused-secret'}}[suffix])
elif 'radio' in args: print('enabled')
elif 'UUID,NAME,TYPE,AUTOCONNECT,DEVICE' in args:
    for suffix in ('012', '013', '014', '015', '016'):
        print('12345678-abcd-1234-abcd-123456789' + suffix + ':Different profile name:802-11-wireless:yes:')
elif 'uuid' in args: print('802-11-wireless.ssid:Fixture\\nconnection.interface-name:wlan0')
''')
    # Records what it was offered. "replaced" leaves like a real wl-copy when
    # another client copies; "refused" fails like a compositor without
    # data-device support; the rest hold until terminated.
    wl_copy = folder / 'wl-copy'
    wl_copy.write_text(f'''#!/usr/bin/env python3
import json, signal, sys, time
from pathlib import Path
offers = Path({str(offers)!r})
data = sys.stdin.read()
record = offers / f"offer-{{len(list(offers.glob('offer-*.json')))}}.json"
record.write_text(json.dumps({{"args": sys.argv[1:], "data": data}}))
if data == 'fixture-refused-secret': sys.exit(1)
def terminated(*_):
    record.with_suffix('.terminated').write_text('')
    sys.exit(0)
signal.signal(signal.SIGTERM, terminated)
deadline = time.time() + (0.3 if data == 'fixture-replaced-secret' else 30)
while time.time() < deadline: time.sleep(0.05)
''')
    for binary in (nmcli, wl_copy):
        binary.chmod(0o700)
    (folder / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int stage: 0
    readonly property var copy: CortetsuSettingsNetwork
    readonly property string base: "12345678-abcd-1234-abcd-123456789"
    function check(value, message) {
        if (!value) { console.error("COPY_FAIL", message); Qt.quit(); }
        return value;
    }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (root.stage === 0) {
                if (copy.profiles.length !== 5) return;
                copy.copyPassword("--help");
                if (!root.check(!copy.secretBusy, "invalid UUID launched query")) return;
                copy.copyPassword(root.base + "012");
                if (!root.check(copy.secretBusy, "copy not pending")) return;
                root.stage = 1;
            } else if (root.stage === 1) {
                if (copy.secretState !== "ready") return;
                if (!root.check(!copy.secretBusy && copy.passwordCopyProcess === null && copy.secretClipboard !== null,
                                "ready without a live sensitive offer")) return;
                root.stage = 2;
            } else if (root.stage === 2) {
                // The lifetime ends the offer that nobody replaced.
                if (copy.secretState !== "idle") return;
                if (!root.check(copy.secretClipboard === null, "expired offer still owned")) return;
                copy.copyPassword(root.base + "013");
                copy.cancelPasswordCopy();
                if (!root.check(!copy.secretBusy && copy.secretState === "idle", "cancel retained the query")) return;
                copy.copyPassword(root.base + "014");
                root.stage = 3;
            } else if (root.stage === 3) {
                if (copy.secretState !== "error") return;
                if (!root.check(!copy.secretBusy && copy.passwordCopyProcess === null, "failed query retained collector")) return;
                copy.copyPassword(root.base + "015");
                root.stage = 4;
            } else if (root.stage === 4) {
                if (copy.secretState !== "ready") return;
                root.stage = 5;
            } else if (root.stage === 5) {
                // Another copy replaced ours: wl-copy left on its own.
                if (copy.secretState !== "idle") return;
                if (!root.check(copy.secretClipboard === null, "replaced offer still tracked")) return;
                copy.copyPassword(root.base + "016");
                root.stage = 6;
            } else {
                if (copy.secretState !== "error") return;
                if (!root.check(copy.secretClipboard === null && copy.secretError.length > 0, "refused offer reported success")) return;
                console.log("COPY_FIXTURE_PASS"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.error("COPY_FAIL", "deadline"); Qt.quit(); } }
}
''')
    env = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}", QT_QPA_PLATFORM='offscreen')
    env.pop('WAYLAND_DISPLAY', None)
    result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml'), '--no-color'], env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=16)
    assert 'fixture-' not in result.stdout, 'a secret reached the shell log'
    assert result.returncode == 0 and 'COPY_FIXTURE_PASS' in result.stdout and 'COPY_FAIL' not in result.stdout, result.stdout
    assert ' WARN' not in result.stdout, result.stdout
    records = sorted(offers.glob('offer-*.json'), key=lambda path: int(path.stem.split('-')[1]))
    offered = [json.loads(path.read_text()) for path in records]
    assert [item['data'] for item in offered] == [SECRET, 'fixture-replaced-secret', 'fixture-refused-secret'], \
        'cancelled or failed queries must not reach the clipboard'
    for item in offered:
        assert {'--sensitive', '--foreground'} <= set(item['args']), 'offer is not marked sensitive'
        assert not any('fixture-' in argument for argument in item['args']), 'secret passed on argv'
    assert records[0].with_suffix('.terminated').exists(), 'expired secret was left on the clipboard'
    assert not records[1].with_suffix('.terminated').exists(), 'expiry must not touch a clipboard the user replaced'
    processes = subprocess.run(['ps', '-eo', 'args'], text=True, stdout=subprocess.PIPE, check=True).stdout
    assert str(nmcli) not in processes and str(wl_copy) not in processes, 'query or clipboard offer survived shell exit'
print('PASS: password copy goes to a sensitive wl-copy via stdin, expires, respects a newer copy and reports failures')
