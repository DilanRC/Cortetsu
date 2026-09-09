#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
installer = (ROOT / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
cli = (ROOT / "scripts/cortetsu").read_text(encoding="utf-8")

# Applying a generation must not tear down Quickshell's tray host implicitly.
assert "systemctl --user restart cortetsu-shell.service" not in installer
assert "no se reinicia automáticamente" in installer
assert "Shell supervision: no se reinicia automáticamente" in installer

# Explicit shell lifecycle operations refuse the known ChatGPT tray crash path
# while the desktop app is open.
assert "shell_restart_allowed" in cli
assert 'pgrep -x ChatGPT' in cli
assert 'CORTETSU_RESTART_SHELL:-0' in cli
assert 'qs ipc --pid "$pid" call cortetsu-shell reload' in cli
assert '[[ "$after" == "$pid" ]]' in cli
assert "Quickshell.reload(false);" in (ROOT / "cortetsu/modules/ShellLifecycle.qml").read_text(encoding="utf-8")
print("Shell application safety eval: 6/6")
