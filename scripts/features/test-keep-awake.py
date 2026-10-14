#!/usr/bin/env python3
"""Keep-awake is an opt-in shell toggle; the installer retires the old permanent unit.

The old cortetsu-keep-awake.service held `systemd-inhibit --what=idle:sleep
--mode=block` for the whole session, so logind answered CanSuspend=inhibited
and Suspend in the session menu did nothing. The idle behaviour of the toggle
itself is exercised by test-cortetsu-idle-runtime.py.
"""
from pathlib import Path
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
installer = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
assert not (repo / "config/systemd/user/cortetsu-keep-awake.service").exists()
assert 'enable --now "$KEEP_AWAKE_UNIT"' not in installer, "the installer must never enable the permanent inhibitor"

# Run the installer's own retirement block against a fake systemctl.
block = re.search(r"\n(# The old unit held.*?\nfi\nif \[\[ -f .*?\nfi)\n", installer, re.S)
assert block, "retirement block not found in install-cortetsu.sh"
for enabled in (True, False):
    with tempfile.TemporaryDirectory(prefix="cortetsu-keep-awake-") as temporary:
        root = Path(temporary)
        units = root / "units"
        units.mkdir()
        (units / "cortetsu-keep-awake.service").write_text("[Service]\n")
        log = root / "calls"
        fake = root / "systemctl"
        # Enabled and active until a disable call lands, like systemd.
        fake.write_text(f'#!/bin/sh\necho "$*" >> {log}\n'
                        f'case "$*" in *is-enabled*|*is-active*) '
                        f'grep -q disable {log} && exit 1; exit {0 if enabled else 1};; esac\n')
        fake.chmod(0o755)
        script = (f'set -euo pipefail\nPATH={root}:$PATH\nSYSTEMD_USER_DIR={units}\n'
                  f'KEEP_AWAKE_UNIT=cortetsu-keep-awake.service\n{block.group(1)}\n')
        result = subprocess.run(["bash", "-c", script], capture_output=True, text=True, check=True)
        calls = log.read_text().splitlines() if log.exists() else []
        disabled = "--user disable --now cortetsu-keep-awake.service" in calls
        assert disabled == enabled, (enabled, calls)
        assert not any(" enable" in call and "disable" not in call for call in calls), calls
        assert not (units / "cortetsu-keep-awake.service").exists(), "the unit file is still loadable"
        assert (units / "cortetsu-keep-awake.service.retired").exists(), "the retired unit is kept for rollback"
        assert ("retirada" in result.stdout) == enabled

inhibitor = (repo / "cortetsu/modules/CortetsuIdleInhibitor.qml").read_text(encoding="utf-8")
assert "systemd-inhibit" not in inhibitor
assert "property bool enabled: false" in inhibitor, "keep-awake must start disabled"
print("PASS: keep-awake starts off, is not a logind inhibitor, and the installer retires the permanent unit")
