#!/usr/bin/env python3
"""Static gating contract for optional Cortetsu 2.0 observer QML."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
shell = (ROOT / "cortetsu/shell.qml").read_text(encoding="utf-8")
bridge = (ROOT / "cortetsu/modules/CortetsuPolicyBridge.qml").read_text(encoding="utf-8")
assert shell.count('source: "modules/CortetsuPolicyBridge.qml"') == 1
assert 'active: Quickshell.env("CORTETSU_V2_IPC_EXPERIMENTAL") === "1"' in shell
assert bridge.count('target: "cortetsu-v2-bridge"') == 1
assert 'op: "snapshot.get"' in bridge
assert 'capabilities: ["snapshot"]' in bridge
assert 'import Quickshell.Io' in bridge
assert 'property string connectionState:' in bridge
assert 'property string state:' not in bridge
assert 'authoritative === false' not in bridge
assert 'Socket {' in bridge
assert 'FileView {' in bridge
assert 'onFileChanged: reload()' in bridge
assert 'Quickshell.execDetached' not in bridge
assert 'Process {' not in bridge
assert 'HyprlandFocusGrab' not in bridge
assert 'PanelWindow' not in bridge
assert 'Window {' not in bridge
assert 'WlrLayershell' not in bridge
assert 'root.sessionId' in bridge and 'root.runtimeDir' in bridge
print("PASS: optional single-instance read-only bridge wiring")
