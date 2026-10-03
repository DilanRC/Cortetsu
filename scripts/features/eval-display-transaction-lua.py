#!/usr/bin/env python3
"""Evaluate the display transaction command boundary."""

from pathlib import Path


root = Path(__file__).resolve().parents[2]
source = (root / "cortetsu/bin/cortetsu-display-transaction").read_text(encoding="utf-8")
checks = {
    "Lua eval translation": "def lua_monitor_command" in source,
    "safe monitor API": '"hyprctl", "eval"' in source,
    "disable path": "disable = true" in source,
    "rollback uses executor": "return execute_plan(original_plan)" in source,
}
missing = [name for name, passed in checks.items() if not passed]
if missing:
    raise SystemExit("FAIL: " + ", ".join(missing))
print(f"Display transaction eval: {len(checks)}/{len(checks)} (100%)")
