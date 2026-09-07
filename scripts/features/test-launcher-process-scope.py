#!/usr/bin/env python3
"""Guard the direct detached desktop-entry launch contract."""

from pathlib import Path


REPO = Path(__file__).resolve().parents[2]
SOURCE = REPO / "cortetsu/modules/launcher/services/Apps.qml"
MANIFEST = REPO / "cortetsu/contracts/patch-debt.tsv"

text = SOURCE.read_text(encoding="utf-8")
manifest = MANIFEST.read_text(encoding="utf-8")

assert '"systemd-run"' not in text
assert '"--scope"' not in text
assert "Array.from(entry.command ?? [])" in text
assert "entry.workingDirectory" in text
assert "Quickshell.execDetached({" in text
assert "command," in text
assert "CortetsuConfig.terminalCommand" in text
assert "wrap_term_launch.sh" in text
assert "GlobalConfig" not in text
assert "modules__launcher__services__Apps.qml.patch" not in manifest

print("PASS: launcher desktop entries use Quickshell direct detached execution")
