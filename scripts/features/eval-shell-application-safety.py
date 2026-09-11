#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
installer = (ROOT / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
cli = (ROOT / "scripts/cortetsu").read_text(encoding="utf-8")

# Applying a generation must not tear down Quickshell's tray host implicitly.
assert "systemctl --user restart cortetsu-shell.service" not in installer
assert "no se reinicia automáticamente" in installer
assert "Shell supervision: no se reinicia automáticamente" in installer

# Explicit shell lifecycle operations are allowed because persistent app
# launches now live in independent user scopes.
assert "shell_restart_allowed" not in cli
assert 'pgrep -x ChatGPT' not in cli
assert "esta operación de ciclo de vida queda bloqueada" not in cli
assert "las aplicaciones persistentes usan scopes independientes" in installer
assert 'qs ipc --pid "$pid" call cortetsu-shell reload' in cli
assert '[[ "$after" == "$pid" ]]' in cli
assert "Quickshell.reload(false);" in (ROOT / "cortetsu/modules/ShellLifecycle.qml").read_text(encoding="utf-8")
print("Shell application safety eval: 7/7")
