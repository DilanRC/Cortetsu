#!/usr/bin/env python3
"""Product eval for fail-closed monitor-local state resolution."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
state = (ROOT / "cortetsu/modules/CortetsuShellState.qml").read_text(encoding="utf-8")
compat = (ROOT / "cortetsu/services/ShellState.qml").read_text(encoding="utf-8")
shortcuts = (ROOT / "cortetsu/modules/Shortcuts.qml").read_text(encoding="utf-8")

checks = {
    "unknown screen is rejected": "if (!screen)" in state and "states[0]?.state" not in state,
    "unknown focused monitor is rejected": "if (!monitor)" in state and "states[0]?.state" not in state,
    "compatibility screen lookup does not cross screens": "?? CortetsuShellState.forActive()" not in compat.split("function forScreen", 1)[1].split("function forActive", 1)[0],
    "compatibility active lookup does not use first screen": "states.instances[0]" not in compat,
    "show-all tolerates no active state": "const state = CortetsuShellState.forActive();\n            if (!state) return;" in shortcuts,
    "full-surface hosts remain monitor-local": "CortetsuShellState.forScreen(modelData)" in (ROOT / "cortetsu/modules/RetainedSurfacesHost.qml").read_text(encoding="utf-8"),
}

assert all(checks.values()), [name for name, passed in checks.items() if not passed]
print(f"Cortetsu screen ownership eval: {sum(checks.values())}/{len(checks)}")
