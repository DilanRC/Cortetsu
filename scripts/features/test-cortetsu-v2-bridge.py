#!/usr/bin/env python3
"""Structural ownership and command contracts for the Cortetsu policy UI."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
bridge = (ROOT / "cortetsu/modules/CortetsuPolicyBridge.qml").read_text(encoding="utf-8")
assert shell.count('source: "modules/CortetsuPolicyBridge.qml"') == 1
assert 'active: root.policySessionAvailable' in shell
assert 'readonly property var policyBridge: policyBridgeLoader.item' in shell
assert bridge.count('target: "cortetsu-v2-bridge"') == 1
assert 'Model.readRequest(' in bridge
assert 'capabilities: ["snapshot", "policy.observe", "explain"]' in bridge
assert 'import Quickshell.Io' in bridge
assert 'property string connectionState:' in bridge
assert 'property string state:' not in bridge
assert 'authoritative === false' not in bridge
assert 'Socket {' in bridge
assert 'FileView {' in bridge
assert 'onFileChanged: reload()' in bridge
assert 'Quickshell.execDetached' not in bridge
assert 'command: ["cortetsu-coordinator", "--observe"]' in bridge
assert 'policyCommand.command = command' in bridge and 'Model.commandFor(' in bridge
for timer in ('requestDeadline', 'actionDeadline', 'reconnectTimer', 'daemonRestart'):
    assert f'id: {timer}' in bridge, timer
assert 'Model.actionConfirmed(' in bridge
assert 'function revokeDomain(domain: string, expectedOwner: string)' in bridge
automation = (ROOT / "cortetsu/modules/settings/sections/AutomationSection.qml").read_text(encoding="utf-8")
assert 'Revocar autorización de esa sesión' in automation
assert 'revokeDomain(domainGroup.modelData.id, domainGroup.activation.owner_session)' in automation
assert '"sh", "-c"' not in bridge and '"bash"' not in bridge
assert 'HyprlandFocusGrab' not in bridge
assert 'PanelWindow' not in bridge
assert 'Window {' not in bridge
assert 'WlrLayershell' not in bridge
assert 'root.sessionId' in bridge and 'root.runtimeDir' in bridge
assert 'Component.onDestruction:' in bridge and 'coordinator.running = false' in bridge
adapter = (ROOT / "cortetsu/services/ConnectivityNmAdapter.qml").read_text()
assert '["cortetsu-connectivity-secret", job.context.uuid]' in adapter
assert 'ConnectivitySecret.py' not in adapter and '"python3"' not in adapter
print("PASS: session-owned coordinator, explicit fixed-argv consent, bounded readback and reconnect")
