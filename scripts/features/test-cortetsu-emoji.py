"""Regression: the emoji keybind and CLI are first-party.

kbEmoji runs `cortetsu emoji -p`, which opens the launcher's emoji mode over
IPC; cortetsu-emoji serves the data (`-f` refreshes it). No fuzzel or
`caelestia emoji` caller remains.
"""
import subprocess
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
cli = repo / "scripts/cortetsu"
emoji_bin = repo / "cortetsu/bin/cortetsu-emoji"
data = repo / "cortetsu/data/emojis.txt"
keybinds = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
cli_text = cli.read_text(encoding="utf-8")

assert emoji_bin.is_file(), "cortetsu/bin/cortetsu-emoji is missing"
assert data.is_file() and data.stat().st_size > 0, "cortetsu/data/emojis.txt is missing or empty"
assert "emoji_cmd()" in cli_text
assert "cortetsu-emoji" in cli_text
assert 'hl.dsp.exec_cmd("cortetsu emoji -p")' in keybinds
assert "caelestia emoji" not in keybinds and "fuzzel" not in keybinds
assert "ipc call customDock emoji" in cli_text
hub = (repo / "cortetsu/modules/BottomHub.qml").read_text(encoding="utf-8")
assert "function emoji(): void" in hub

# The CLI wrapper rejects unknown flags the same way screenshot/record do.
result = subprocess.run(["bash", str(cli), "emoji", "--bad"], text=True, capture_output=True)
assert result.returncode != 0 and "opción de emoji desconocida" in result.stderr
for extra in (["-p", "--bad"], ["-f", "--bad"]):
    result = subprocess.run(["bash", str(cli), "emoji", *extra], text=True, capture_output=True)
    assert result.returncode != 0 and "opción de emoji desconocida: --bad" in result.stderr, extra

# The binary itself: dump mode prints the local data file untouched.
result = subprocess.run(
    ["bash", str(emoji_bin)], text=True, capture_output=True,
    env={"CORTETSU_EMOJI_DATA": str(data), "PATH": "/usr/bin:/bin", "HOME": str(Path.home())},
)
assert result.returncode == 0
assert result.stdout == data.read_text(encoding="utf-8")

print("PASS: emoji keybind opens the launcher; no fuzzel or caelestia caller remains")
