from pathlib import Path

repo = Path(__file__).resolve().parents[2]
helper = (repo / "cortetsu/bin/cortetsu-record").read_text(encoding="utf-8")
service = (repo / "cortetsu/services/Recorder.qml").read_text(encoding="utf-8")
module = (repo / "cortetsu/modules/CortetsuRecorder.qml").read_text(encoding="utf-8")
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
cli = (repo / "scripts/cortetsu").read_text(encoding="utf-8")
keybinds = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")

assert 'RECORDER = "gpu-screen-recorder"' in helper
assert "os.kill(pid, signum)" in helper and "pkill" not in helper
assert '"cortetsu-record", "start"' in service
assert '"cortetsu-record", "pause"' in service
assert '"cortetsu-record", "stop"' in service
assert 'command: ["cortetsu-record", "status"]' in service
assert '"cortetsu-record", "stop"' in module
assert "CortetsuRecorder.running" in hub and "CortetsuRecorder.stop()" in hub
assert "record) record_cmd" in cli
assert 'create_bind(vars.kbRecord, hl.dsp.exec_cmd("cortetsu-record start"))' in keybinds
assert 'create_bind(vars.kbRecordSound, hl.dsp.exec_cmd("cortetsu-record start -s"))' in keybinds
assert 'create_bind(vars.kbRecordRegion, hl.dsp.exec_cmd("cortetsu-record start -r"))' in keybinds
assert 'caelestia record' not in keybinds
print("PASS: recorder status and stop use the owned exact-process contract")
