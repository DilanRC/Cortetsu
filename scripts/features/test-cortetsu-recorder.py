from pathlib import Path
import re

repo = Path(__file__).resolve().parents[2]
helper = (repo / "cortetsu/bin/cortetsu-record").read_text(encoding="utf-8")
module = (repo / "cortetsu/modules/CortetsuRecorder.qml").read_text(encoding="utf-8")
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
cli = (repo / "scripts/cortetsu").read_text(encoding="utf-8")
keybinds = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")

assert 'RECORDER = "gpu-screen-recorder"' in helper
assert "def signal_owned" in helper and "pidof" not in helper
assert "STATE_PATH" in helper and "outputTempPath" in helper
assert '"starttime"' in helper and "rsplit(\")\", 1)" in helper
assert "atomic_write_json" in helper and "state_lock" in helper
assert 'return 75' in helper and 'busy:' in helper
assert '"cortetsu-record", "start"' in module
assert '"cortetsu-record", "pause"' in module
assert '"cortetsu-record", "stop"' in module
assert 'watchChanges: false' in module and 'stateFile.reload()' in module
assert 'command: ["cortetsu-record", "status"]' in module
card = (repo / "cortetsu/base/modules/utilities/cards/Record.qml").read_text(encoding="utf-8")
assert not re.search(r"(?<!Cortetsu)Recorder\.(running|paused)", card)
assert "CortetsuRecorder." in card
assert 'Timer { interval: 2000' not in module
assert '"cortetsu-record", "stop"' in module
assert "CortetsuRecorder.running" in hub and "CortetsuRecorder.stop()" in hub
assert "record) record_cmd" in cli
assert 'create_bind(vars.kbRecord, hl.dsp.exec_cmd("cortetsu-record start"))' in keybinds
assert 'create_bind(vars.kbRecordSound, hl.dsp.exec_cmd("cortetsu-record start -s"))' in keybinds
assert 'create_bind(vars.kbRecordRegion, hl.dsp.exec_cmd("cortetsu-record start -r"))' in keybinds
assert 'caelestia record' not in keybinds
print("PASS: recorder status and stop use the owned exact-process contract")
