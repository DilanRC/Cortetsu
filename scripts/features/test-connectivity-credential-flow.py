"""Verify credential save failures and cancellation cannot activate a profile."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
for mode in ('save-failed', 'missing-proof', 'queued-cancel', 'running-cancel'):
    with tempfile.TemporaryDirectory(prefix='cortetsu-credential-flow-') as temporary:
        folder = Path(temporary)
        for name in ('ConnectivityNmAdapter.qml', 'ConnectivityPolicy.js'):
            shutil.copy(repo / 'cortetsu/services' / name, folder / name)
        (folder / 'services').mkdir()
        state = folder / 'state.json'
        state.write_text('{}')
        (folder / 'nmcli').write_text('''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
assert 'fixture-sensitive-value' not in ' '.join(args)
if args == ['monitor']:
    while True: time.sleep(60)
if 'up' in args:
    state = Path(os.environ['CREDENTIAL_FLOW_STATE'])
    state.write_text(json.dumps({'activated': True}))
elif 'radio' in args: print('enabled')
''')
        (folder / 'nmcli').chmod(0o700)
        (folder / 'services/ConnectivitySecret.py').write_text('''import json, os, sys, time
from pathlib import Path
assert len(sys.argv) == 2 and 'fixture-sensitive-value' not in ' '.join(sys.argv)
assert sys.stdin.read() == 'fixture-sensitive-value'
state = Path(os.environ['CREDENTIAL_FLOW_STATE'])
state.write_text(json.dumps({'helperStarted': True}))
mode = os.environ['CREDENTIAL_FLOW_MODE']
if mode == 'running-cancel': time.sleep(5)
if mode == 'missing-proof': print('UNVERIFIED'); sys.exit(0)
print('credential-save-failed', file=sys.stderr)
sys.exit(4)
''')
        cancel = mode.endswith('cancel')
        (folder / 'shell.qml').write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    property int completions: 0
    property bool cancelled: false
    ConnectivityNmAdapter {
        id: adapter
        onMutationFinished: (id, success, code, message, retryable) => {
            if (id !== 9) return;
            root.completions++;
            if (success || code !== "credential-save-failed") { console.error("FLOW_FAIL", "unverified credentials accepted"); Qt.quit(); return; }
            console.log("FLOW_PASS"); Qt.quit();
        }
    }
    Component.onCompleted: {
        adapter.saveAndActivate(9, "12345678-abcd-1234-abcd-123456789012", "wlan0", "fixture-sensitive-value");
        MODE_QUEUED_CANCEL
    }
    Timer {
        interval: 50; running: MODE_RUNNING_CANCEL; repeat: true
        onTriggered: if (adapter.worker.running && adapter.job?.kind === "save-secret") {
            adapter.cancelOperation(9); root.cancelled = true; stop();
        }
    }
    Timer {
        interval: 900; running: MODE_ANY_CANCEL
        onTriggered: {
            if (!root.cancelled || root.completions !== 0 || adapter.job?.kind === "save-secret" || adapter.queue.some(job => job.kind === "save-secret")) {
                console.error("FLOW_FAIL", "cancellation retained sensitive job or completed it"); Qt.quit(); return;
            }
            console.log("FLOW_PASS"); Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("FLOW_FAIL", "deadline"); Qt.quit(); } }
}
'''.replace('MODE_QUEUED_CANCEL', 'adapter.cancelOperation(9); root.cancelled = true;' if mode == 'queued-cancel' else '')
           .replace('MODE_RUNNING_CANCEL', 'true' if mode == 'running-cancel' else 'false')
           .replace('MODE_ANY_CANCEL', 'true' if cancel else 'false'))
        env = dict(os.environ, PATH=f"{folder}:{os.environ['PATH']}", QT_QPA_PLATFORM='offscreen', CREDENTIAL_FLOW_STATE=str(state), CREDENTIAL_FLOW_MODE=mode)
        env.pop('WAYLAND_DISPLAY', None)
        result = subprocess.run(['quickshell', '-p', str(folder / 'shell.qml'), '--no-color'], env=env, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=8)
        assert result.returncode == 0 and 'FLOW_PASS' in result.stdout and 'FLOW_FAIL' not in result.stdout, (mode, result.stdout)
        assert 'fixture-sensitive-value' not in result.stdout, result.stdout
        assert ' WARN' not in result.stdout, result.stdout
        recorded = json.loads(state.read_text())
        assert not recorded.get('activated'), (mode, recorded)
        if mode == 'queued-cancel': assert not recorded.get('helperStarted'), recorded
print('PASS: helper failure, missing proof and queued/in-flight cancellation never activate')
