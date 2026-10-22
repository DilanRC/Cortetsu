#!/usr/bin/env python3
"""Real QML socket/process lifecycle in an isolated home; no desktop mutation.

The fake coordinator owns a private Unix socket and the fake policy CLI writes
only fixture activation data. This exercises the production QML unchanged.
"""
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]

COORDINATOR = r'''#!/usr/bin/env python3
import fcntl, json, os, signal, socket, sys, time
from pathlib import Path
assert sys.argv[1:] == ['--observe']
root = Path(os.environ['POLICY_FIXTURE'])
runtime = Path(os.environ['XDG_RUNTIME_DIR']) / 'cortetsu'
runtime.mkdir(mode=0o700, exist_ok=True)
lock = (runtime / 'fixture.lock').open('a')
try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError: sys.exit(0)
counter = root / 'starts'
epoch = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(epoch))
(root / 'pid').write_text(str(os.getpid()))
session = os.environ['HYPRLAND_INSTANCE_SIGNATURE']
sockpath = runtime / ('cortetsu-' + session + '.sock')
descriptor = runtime / ('bridge-' + session + '.json')
sockpath.unlink(missing_ok=True)
listener = socket.socket(socket.AF_UNIX)
listener.bind(str(sockpath)); listener.listen(4); listener.settimeout(20)
def save(path, data):
    temporary = path.with_suffix('.new')
    temporary.write_text(json.dumps(data)); temporary.chmod(0o600); temporary.replace(path)
save(descriptor, dict(protocol='cortetsu.ipc', session_id=session, session_epoch=epoch, socket=str(sockpath)))
scenario = os.environ['POLICY_SCENARIO']
def stop(*_): raise SystemExit(0)
signal.signal(signal.SIGTERM, stop)
try:
    while True:
        conn, _ = listener.accept()
        conn.settimeout(10)
        with conn, conn.makefile('r', encoding='utf-8') as stream:
            hello = json.loads(stream.readline())
            assert hello['session_id'] == session and hello['session_epoch'] == epoch
            ack = dict(type='hello_ack', protocol='cortetsu.ipc', version=dict(major=1,minor=0),
                session_id=session, session_epoch=epoch + (1 if scenario == 'mismatch' else 0),
                capabilities=['snapshot','policy.observe','explain'], max_frame_bytes=65536)
            conn.sendall((json.dumps(ack)+'\n').encode())
            for line in stream:
                request = json.loads(line)
                assert request['op'] in ['snapshot.get','policy.list','explain.get']
                assert request['session_id'] == session and request['session_epoch'] == epoch
                if scenario == 'timeout' and request['op'] == 'snapshot.get': continue
                if request['op'] == 'snapshot.get':
                    state = json.loads((root/'activation.json').read_text()) if (root/'activation.json').exists() else {}
                    body = dict(mode='coordinator', authoritative=True, stream_stale=False, activations=state, decisions=[])
                elif request['op'] == 'policy.list': body = dict(rules=[])
                else: body = dict(decisions=[])
                reply = dict(type='response', protocol='cortetsu.ipc', version=dict(major=1,minor=0),
                    id=request['id'], outcome='read', body=body)
                conn.sendall((json.dumps(reply)+'\n').encode())
                if scenario == 'flow' and epoch == 1 and request['op'] == 'snapshot.get' and (root/'restart').exists():
                    time.sleep(.15)
                    sys.exit(0)
except (BrokenPipeError, ConnectionResetError): pass
finally:
    listener.close(); descriptor.unlink(missing_ok=True); sockpath.unlink(missing_ok=True)
'''

POLICY = r'''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
root = Path(os.environ['POLICY_FIXTURE'])
operation, domain, *rest = sys.argv[1:]
assert operation in ['enable','disable','override','revoke'] and domain in ['notifications','gamemode','power','display']
session = os.environ['HYPRLAND_INSTANCE_SIGNATURE']
assert session == 'fixture-session'
with (root/'calls').open('a') as stream: stream.write(json.dumps(sys.argv[1:])+'\n')
path = root/'activation.json'
state = json.loads(path.read_text()) if path.exists() else {}
record = state.setdefault(domain,dict(enabled=False,owner_session='',manual_override_until_unix_ms=0))
if operation == 'revoke':
    assert len(rest) == 1
    if record['owner_session'] != rest[0]:
        print('SESSION_MISMATCH', file=sys.stderr); sys.exit(1)
    record['enabled'] = False
    record['owner_session'] = ''
    reply = dict(domain=domain,enabled=False,owner_session='',revoked_owner_session=rest[0],session_id=session)
elif operation == 'override':
    assert len(rest) == 1 and 0 <= int(rest[0]) <= 604800
    until = int(time.time()*1000)+int(rest[0])*1000 if int(rest[0]) else 0
    record['manual_override_until_unix_ms'] = until
    reply = dict(domain=domain,manual_override_until_unix_ms=until)
else:
    assert not rest
    record['enabled'] = operation == 'enable'
    record['owner_session'] = session if record['enabled'] else ''
    reply = dict(domain=domain,enabled=record['enabled'],session_id=session)
if os.environ['POLICY_SCENARIO'] != 'readback-failure':
    temporary = path.with_suffix('.new'); temporary.write_text(json.dumps(state)); temporary.replace(path)
if operation == 'disable': (root/'restart').touch()
print(json.dumps(reply))
'''

SHELL = r'''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: root
    readonly property string scenario: Quickshell.env("POLICY_SCENARIO")
    property int step: 0
    property int initialEpoch: 0
    property bool sawNegotiated: false
    property bool sawPending: false
    property bool sawDisconnect: false
    function fail(reason) { console.log("POLICY_FAIL", reason); Qt.quit(); }
    function pass() { console.log("POLICY_PASS", scenario); Qt.quit(); }
    CortetsuPolicyBridge { id: bridge }
    Timer {
        interval: 30; repeat: true; running: true
        onTriggered: {
            if (bridge.negotiated) root.sawNegotiated = true;
            if (root.scenario === "timeout") {
                if (bridge.canChange) { root.fail("a missing snapshot allowed a change"); return; }
                if (root.sawNegotiated && !bridge.usable) root.pass();
                return;
            }
            if (root.scenario === "mismatch") {
                if (bridge.usable || bridge.canChange) root.fail("a foreign epoch negotiated");
                return;
            }
            if (root.scenario === "readback-failure") {
                if (root.step === 0 && bridge.canChange) { root.step = 1; bridge.setDomainEnabled("gamemode", true); }
                else if (root.step === 1) {
                    if (bridge.activation("gamemode").enabled) { root.fail("an unconfirmed write changed the display"); return; }
                    if (bridge.pendingDomain === "gamemode") root.sawPending = true;
                    if (root.sawPending && bridge.pendingDomain === "" && bridge.lastError.length > 0) root.pass();
                }
                return;
            }
            if (root.step === 0 && bridge.canChange) {
                root.initialEpoch = bridge.descriptor.session_epoch;
                if (bridge.activation("gamemode").enabled) { root.fail("domain was enabled by startup"); return; }
                bridge.setDomainEnabled("gamemode; exit", true);
                if (bridge.pendingDomain !== "") { root.fail("invalid domain accepted"); return; }
                root.step = 1; bridge.setDomainEnabled("gamemode", true);
                if (bridge.activation("gamemode").enabled) root.fail("optimistic state before readback");
            } else if (root.step === 1 && bridge.canChange && bridge.activation("gamemode").enabled) {
                root.step = 2; bridge.overrideDomain("gamemode", 900);
            } else if (root.step === 2 && bridge.canChange && bridge.activation("gamemode").manual_override_until_unix_ms > 0) {
                root.step = 3; bridge.overrideDomain("gamemode", 0);
            } else if (root.step === 3 && bridge.canChange && bridge.activation("gamemode").manual_override_until_unix_ms === 0) {
                root.step = 4; bridge.setDomainEnabled("gamemode", false);
            } else if (root.step === 4 && !bridge.usable) {
                root.sawDisconnect = true;
            } else if (root.step === 4 && root.sawDisconnect && bridge.canChange && bridge.descriptor.session_epoch > root.initialEpoch) {
                if (bridge.activation("gamemode").enabled) root.fail("disabled domain came back after reconnect");
                else {
                    bridge.revokeDomain("power", "changed-owner");
                    if (bridge.pendingDomain !== "") { root.fail("stale expected owner was submitted"); return; }
                    root.step = 5; bridge.revokeDomain("power", "expired-session");
                    if (!bridge.activation("power").enabled) root.fail("revocation changed state before readback");
                }
            } else if (root.step === 5 && bridge.canChange && bridge.activation("power").owner_session === "") {
                if (bridge.activation("power").enabled) root.fail("revocation automatically granted this session consent");
                else root.pass();
            }
        }
    }
    Timer { interval: 2500; running: root.scenario === "mismatch"; onTriggered: root.pass() }
    Timer { interval: 21000; running: true; onTriggered: root.fail("scenario deadline") }
}
'''

for scenario in ("flow", "timeout", "mismatch", "readback-failure"):
    with tempfile.TemporaryDirectory(prefix="cortetsu-policy-qml-") as temporary:
        folder = Path(temporary)
        for file in ("CortetsuPolicyBridge.qml", "CortetsuPolicyModel.js"):
            shutil.copyfile(ROOT / "cortetsu/modules" / file, folder / file)
        runtime = folder / "runtime"
        runtime.mkdir(mode=0o700)
        binaries = folder / "bin"
        binaries.mkdir()
        for name, source in (("cortetsu-coordinator", COORDINATOR), ("cortetsu-policy", POLICY)):
            path = binaries / name
            path.write_text(source)
            path.chmod(0o700)
        (folder / "shell.qml").write_text(SHELL)
        if scenario == "flow":
            (folder / "activation.json").write_text(json.dumps({"power": {
                "enabled": True, "owner_session": "expired-session", "manual_override_until_unix_ms": 0}}))
        environment = {**os.environ, "QT_QPA_PLATFORM": "offscreen", "HOME": str(folder),
            "XDG_RUNTIME_DIR": str(runtime), "XDG_CONFIG_HOME": str(folder / "config"),
            "XDG_STATE_HOME": str(folder / "state"), "XDG_CACHE_HOME": str(folder / "cache"),
            "HYPRLAND_INSTANCE_SIGNATURE": "fixture-session", "POLICY_FIXTURE": str(folder),
            "POLICY_SCENARIO": scenario, "PATH": f"{binaries}:{os.environ['PATH']}"}
        process = subprocess.Popen(["quickshell", "-p", str(folder / "shell.qml"), "--no-color"],
            env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        try:
            output, _ = process.communicate(timeout=25)
            assert process.returncode == 0 and f"POLICY_PASS {scenario}" in output, output
            assert "POLICY_FAIL" not in output and "ReferenceError" not in output and "TypeError" not in output, output
            calls = [json.loads(line) for line in (folder / "calls").read_text().splitlines()] if (folder / "calls").exists() else []
            if scenario == "flow":
                assert calls == [["enable", "gamemode"], ["override", "gamemode", "900"], ["override", "gamemode", "0"],
                    ["disable", "gamemode"], ["revoke", "power", "expired-session"]], calls
                assert int((folder / "starts").read_text()) >= 2
            elif scenario == "readback-failure":
                assert calls == [["enable", "gamemode"]], calls
            else:
                assert calls == [], calls
            print(f"PASS: policy QML {scenario}")
        finally:
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait(timeout=3)
