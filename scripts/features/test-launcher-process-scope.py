#!/usr/bin/env python3
"""Guard the isolated persistent desktop-entry launch contract."""

from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "cortetsu/modules/launcher/services/Apps.qml"
ACTION_SOURCE = REPO / "cortetsu/modules/launcher/services/Actions.qml"
APP_LIST = REPO / "cortetsu/modules/launcher/AppList.qml"
RECORDING_LIST = REPO / "cortetsu/base/modules/utilities/cards/RecordingList.qml"
HELPER = REPO / "cortetsu/services/CortetsuProcessLauncher.qml"
SCRIPT = REPO / "cortetsu/bin/cortetsu-launch-persistent"
MANIFEST = REPO / "cortetsu/contracts/patch-debt.tsv"

text = SOURCE.read_text(encoding="utf-8")
actions = ACTION_SOURCE.read_text(encoding="utf-8")
app_list = APP_LIST.read_text(encoding="utf-8")
recording_list = RECORDING_LIST.read_text(encoding="utf-8")
helper = HELPER.read_text(encoding="utf-8")
script = SCRIPT.read_text(encoding="utf-8")
manifest = MANIFEST.read_text(encoding="utf-8")

assert "Array.from(entry.command ?? [])" in text
assert "entry.workingDirectory" in text
assert "CortetsuProcessLauncher.launchPersistent" in text
assert "CortetsuProcessLauncher.launchPersistent" in actions
assert "CortetsuProcessLauncher.launchPersistent" in app_list
assert "CortetsuProcessLauncher.launchPersistent" in recording_list
assert "launchPersistent" in helper
assert "cortetsu-launch-persistent" in helper
assert "/usr/bin/systemd-run" in script
assert "--scope" in script and "--collect" in script
assert "--)" in script
assert "CortetsuConfig.terminalCommand" in text
assert "wrap_term_launch.sh" in text
assert "GlobalConfig" not in text
assert "modules__launcher__services__Apps.qml.patch" not in manifest

print("PASS: launcher desktop entries use isolated persistent user scopes")
