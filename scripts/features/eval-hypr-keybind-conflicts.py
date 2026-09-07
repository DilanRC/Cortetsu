from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
variables = (ROOT / "dotfiles/home/.config/hypr/variables.lua").read_text(encoding="utf-8")
keybinds = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
user = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")
assert variables.count('kbBrowser                  = "SUPER + B"') == 1
assert variables.count('kbColorPicker              = "SUPER + SHIFT + P"') == 1
assert "create_bind(vars.kbClipboard," not in keybinds
assert "create_bind(vars.kbClipboardDel," not in keybinds
assert '"SUPER + CTRL + " .. key' not in user
print("PASS: keybind conflict eval has one owner per migrated chord")
