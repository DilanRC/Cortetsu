from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
variables = (ROOT / "dotfiles/home/.config/hypr/variables.lua").read_text(encoding="utf-8")
keybinds = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
user = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")

assert 'kbBrowser                  = "SUPER + B"' in variables
assert 'kbColorPicker              = "SUPER + SHIFT + P"' in variables
assert 'create_bind(vars.kbClipboard,' not in keybinds
assert 'create_bind(vars.kbClipboardDel,' not in keybinds
assert '"SUPER + CTRL + " .. key' not in user
assert '"SUPER + W"' in user and "linux-wallpaper-engine-once" in user
assert '"SUPER + V"' in user and 'cortetsu:clipboard' in user
assert '"SUPER + SHIFT + C"' in user and 'cortetsu:calendar' in user
print("PASS: browser, calendar, color picker and clipboard keybind ownership is single-layer")
