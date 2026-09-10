import re
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
variables = (ROOT / "dotfiles/home/.config/hypr/variables.lua").read_text(encoding="utf-8")
keybinds = (ROOT / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
user = (ROOT / "config/hypr-user.lua").read_text(encoding="utf-8")


def literal_bindings(source: str) -> list[str]:
    values = re.findall(r"(?:create_bind|hl\.bind)\(\s*[\"']([^\"']+)[\"']", source)
    values = [value for value in values if not value.endswith(" + ")]
    if '{ "SUPER + SLASH", "SUPER + SHIFT + 7" }' in source:
        values.extend(("SUPER + SLASH", "SUPER + SHIFT + 7"))
    return values


literal_counts = Counter(literal_bindings(keybinds) + literal_bindings(user))
if "create_bind(vars.kbScreenshot" in keybinds:
    literal_counts["Print"] += 1
single_owner = all(literal_counts[key] == 1 for key in ("SUPER + SLASH", "SUPER + SHIFT + 7", "SUPER + I", "Print"))
assert variables.count('kbBrowser                  = "SUPER + B"') == 1
assert variables.count('browser                    = "brave-origin"') == 1
assert variables.count('kbColorPicker              = "SUPER + SHIFT + P"') == 1
assert "create_bind(vars.kbClipboard," not in keybinds
assert "create_bind(vars.kbClipboardDel," not in keybinds
assert '"SUPER + CTRL + " .. key' not in user
assert 'cortetsu shell ipc clipboard toggle' in user
assert 'move_key = "SUPER + SHIFT + F7"' in user
assert single_owner, literal_counts
print("PASS: keybind conflict eval has one owner per migrated chord")
