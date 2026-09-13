#!/usr/bin/env python3
"""Guard display preview execution against the active non-legacy parser."""

from importlib.machinery import SourceFileLoader
from pathlib import Path


root = Path(__file__).resolve().parents[2]
path = root / "cortetsu/bin/cortetsu-display-transaction"
module = SourceFileLoader("display_transaction", str(path)).load_module()

command = [
    "hyprctl", "keyword", "monitor",
    "eDP-1,1920x1080@60Hz,0x0,1,transform,0,bitdepth,8,cm,srgb,vrr,0",
]
translated = module.lua_monitor_command(command)
assert translated[:2] == ["hyprctl", "eval"]
assert 'hl.monitor({' in translated[2]
assert 'output = "eDP-1"' in translated[2]
assert 'mode = "1920x1080@60Hz"' in translated[2]
assert 'position = "0x0"' in translated[2]
assert "scale = 1" in translated[2]
assert "bitdepth = 8" in translated[2]
print("PASS: display preview translates monitor plans to Lua eval")
