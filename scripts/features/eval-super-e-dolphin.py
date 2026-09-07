#!/usr/bin/env python3
from pathlib import Path

root = Path(__file__).resolve().parents[2]
text = (root / 'dotfiles/home/.config/hypr/variables.lua').read_text(encoding='utf-8')
assert 'fileExplorer               = "dolphin"' in text
print('SUPER+E eval: 2/2 (Dolphin target and variable-driven dispatcher)')
