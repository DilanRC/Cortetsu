#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
source = (root / 'dotfiles/home/.config/hypr/variables.lua').read_text(encoding='utf-8')
assert 'fileExplorer               = "dolphin"' in source, 'SUPER+E does not resolve to Dolphin'
assert 'create_bind(vars.kbFileExplorer, hl.dsp.exec_cmd(vars.fileExplorer))' in (root / 'dotfiles/home/.config/hypr/hyprland/keybinds.lua').read_text(encoding='utf-8')
print('PASS: SUPER+E effective source target is Dolphin')
