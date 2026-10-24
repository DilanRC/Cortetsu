#!/usr/bin/env python3
"""Installation must preserve the active power profile until an explicit switch."""
from __future__ import annotations

import os
import re
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
INSTALLER = (REPO / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
MIGRATOR = REPO / "scripts/migrate-cortetsu-v2.sh"

assert 'systemctl --user enable cortetsu-power-auto.service' in INSTALLER
assert not any(
    re.match(
        r"\s*(?:if\s+)?systemctl\s+--user\s+(?:start|restart|try-restart|enable\s+--now|disable\s+--now)\s+cortetsu-power-auto\.service\b",
        line,
    )
    for line in INSTALLER.splitlines()
)
assert 'restart explicitly to adopt the new generation (systemctl --user restart cortetsu-power-auto.service)' in INSTALLER

with tempfile.TemporaryDirectory(prefix="cortetsu-power-install-") as tmp:
    root = Path(tmp)
    home, config, data, state, cache, bindir = (root / name for name in ("home", "config", "data", "state", "cache", "bin"))
    units = config / "systemd/user"
    for path in (home, units, data, state, cache, bindir):
        path.mkdir(parents=True, exist_ok=True)
    (units / "caerice-power-auto.service").write_text("[Service]\nExecStart=/old/daemon\n", encoding="utf-8")
    calls = root / "systemctl.log"
    fake_systemctl = bindir / "systemctl"
    fake_systemctl.write_text(
        '#!/bin/sh\nprintf "%s\\n" "$*" >> "$SYSTEMCTL_LOG"\n'
        'case "$*" in *" is-enabled caerice-power-auto.service") exit 0;; '
        '*" is-active --quiet caerice-power-auto.service") exit 0;; esac\n'
        'exit 0\n',
        encoding="utf-8",
    )
    fake_systemctl.chmod(0o755)
    fake_secret_tool = bindir / "secret-tool"
    fake_secret_tool.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    fake_secret_tool.chmod(0o755)

    env = os.environ.copy()
    env.update(
        HOME=str(home), XDG_CONFIG_HOME=str(config), XDG_DATA_HOME=str(data),
        XDG_STATE_HOME=str(state), XDG_CACHE_HOME=str(cache),
        SYSTEMCTL_LOG=str(calls), PATH=f"{bindir}:/usr/bin:/bin",
    )
    result = subprocess.run(
        ["bash", str(MIGRATOR)], env=env, text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, result.stderr
    power_calls = [line for line in calls.read_text(encoding="utf-8").splitlines() if "caerice-power-auto.service" in line]
    assert "--user disable caerice-power-auto.service" in power_calls, power_calls
    assert all("--now" not in line for line in power_calls), power_calls
    assert "Legacy power automation remains active." in result.stdout
    assert "systemctl --user stop caerice-power-auto.service && systemctl --user start cortetsu-power-auto.service" in result.stdout
    assert (data / "cortetsu/.power-auto-was-enabled").is_file()

print("PASS: install does not restart power-auto; migration leaves its active process running and gives an explicit switch command")
