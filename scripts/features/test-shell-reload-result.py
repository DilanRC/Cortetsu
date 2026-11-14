#!/usr/bin/env python3
"""`cortetsu shell reload` reports what Quickshell did with the new files.

The reload IPC returns before the load. A configuration that fails to load
leaves the previous one running in the same PID, so a check of the PID alone
reported success while the session kept the old generation (2026-11-14:
"Lean is not a type" after `cortetsu install`). Fake systemctl, qs and
journalctl stand in for the session; nothing reaches the real shell.
"""
from __future__ import annotations

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[2]

STUBS = {
    "systemctl": """#!/bin/bash
case "$*" in
  *"show cortetsu-shell.service -p MainPID --value"*) echo 4242 ;;
  *"is-active --quiet cortetsu-shell.service"*) exit 0 ;;
  *) echo "systemctl inesperado: $*" >&2; exit 9 ;;
esac
""",
    # The reload request appends what Quickshell would log for this case.
    "qs": """#!/bin/bash
[[ "$*" == "ipc --pid 4242 call cortetsu-shell reload" ]] || { echo "qs inesperado: $*" >&2; exit 9; }
printf '%b' "$RELOAD_LOG" >> "$JOURNAL"
""",
    "journalctl": """#!/bin/bash
[[ "$NO_CURSOR" == 1 ]] && exit 1
case "$*" in
  *--show-cursor*) echo "-- cursor: s=1" ;;
  *--after-cursor=s=1*) cat "$JOURNAL" ;;
  *) echo "journalctl inesperado: $*" >&2; exit 9 ;;
esac
""",
}


def run(tmp: Path, reload_log: str, no_cursor: bool = False) -> subprocess.CompletedProcess:
    journal = tmp / "journal"
    # An earlier successful load is in the journal before the cursor; it
    # must not count.
    journal.write_text("")
    env = dict(os.environ, PATH=f"{tmp / 'stubs'}:{os.environ['PATH']}", CORTETSU_REPO_ROOT=str(REPO),
               JOURNAL=str(journal), RELOAD_LOG=reload_log, NO_CURSOR="1" if no_cursor else "0")
    return subprocess.run([str(tmp / "bin/cortetsu"), "shell", "reload"], env=env, capture_output=True, text=True,
                          timeout=30)


with tempfile.TemporaryDirectory(prefix="cortetsu-shell-reload-") as t:
    tmp = Path(t)
    (tmp / "bin").mkdir()
    (tmp / "stubs").mkdir()
    shutil.copy(REPO / "scripts/cortetsu", tmp / "bin/cortetsu")
    platform = tmp / "bin/cortetsu-platform"
    platform.write_text("#!/bin/sh\nexit 0\n")
    platform.chmod(0o755)
    for name, body in STUBS.items():
        stub = tmp / "stubs" / name
        stub.write_text(body)
        stub.chmod(0o755)

    ok = run(tmp, r"  INFO: Reloading configuration...\n  INFO: Configuration Loaded\n")
    assert ok.returncode == 0, ok.stderr
    assert "recarga suave completada en el mismo proceso (4242)" in ok.stdout, ok.stdout

    failed = run(tmp, r"  INFO: Reloading configuration...\n\033[31m ERROR\033[0m: Failed to load configuration\n"
                      r"\033[31m ERROR\033[0m:   caused by @modules/CortetsuBottomHubView.qml[201:5]: Lean is not a type\n")
    assert failed.returncode != 0, failed.stdout
    assert "recarga suave completada" not in failed.stdout, failed.stdout
    assert "rechazó la generación nueva" in failed.stderr, failed.stderr
    assert "Lean is not a type" in failed.stderr, failed.stderr
    assert "\033[" not in failed.stderr, "los códigos de color del journal llegan al usuario"

    blind = run(tmp, r"  INFO: Configuration Loaded\n", no_cursor=True)
    assert blind.returncode != 0 and "no se puede leer el journal" in blind.stderr, blind

print("PASS: cortetsu shell reload succeeds only when Quickshell loads the new configuration")
