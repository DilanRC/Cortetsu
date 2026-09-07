#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import tomllib
from pathlib import Path

repo = Path(__file__).resolve().parents[2]

subprocess.run(["python3", str(repo / "core/theme.py"), "check", "--repo", str(repo)], check=True)

kitty = (repo / "dotfiles/imported/desktop/home/.config/kitty/kitty.conf").read_text(encoding="utf-8")
assert "include cortetsu-theme.conf" in kitty
assert "state/caelestia/theme" not in kitty
assert "kitty-caerice" not in kitty
assert "include caelestia-theme.conf" not in kitty

with (repo / "dotfiles/manifest.toml").open("rb") as handle:
    manifest = tomllib.load(handle)
entries = {entry["target"]: entry for entry in manifest["entry"]}
assert entries[".config/kitty/cortetsu-theme.conf"]["source"].startswith("dotfiles/generated/theme/")
assert entries[".config/gtk-3.0/cortetsu-colors.css"]["source"].startswith("dotfiles/generated/theme/")
assert entries[".config/gtk-4.0/cortetsu-colors.css"]["source"].startswith("dotfiles/generated/theme/")
assert entries[".config/kdeglobals"]["source"].startswith("dotfiles/generated/theme/")

for relative in (
    "dotfiles/imported/desktop/home/.config/gtk-3.0/gtk.css",
    "dotfiles/imported/desktop/home/.config/gtk-4.0/gtk.css",
):
    text = (repo / relative).read_text(encoding="utf-8")
    assert text.startswith('@import "cortetsu-colors.css";')
    assert "@define-color accent_color #c6c6c6" not in text

for relative in (
    "dotfiles/imported/desktop/home/.config/gtk-3.0/thunar.css",
    "dotfiles/imported/desktop/home/.config/gtk-4.0/thunar.css",
):
    text = (repo / relative).read_text(encoding="utf-8")
    assert "@accent_color" in text
    assert "#c6c6c6" not in text
    assert "#0e0e0e" not in text

kde = (repo / "dotfiles/generated/theme/home/.config/kdeglobals").read_text(encoding="utf-8")
assert "ColorScheme=Cortetsu" in kde
assert "Name=Cortetsu" in kde
assert "Caelestia" not in kde

design = (repo / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
assert 'var colorSumi = "#0B0D10"' in design
assert 'var colorVermillion = "#D64B32"' in design
assert "var motionFastMs = 80" in design
assert "var motionStandardMs = 120" in design
assert "var motionPanelMs = 170" in design
assert "var hoverScale = 1.025" in design

install = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
assert "core/theme.py\" check" in install
assert "core/theme.py\" adopt" in install
assert "install-theme-bridge.py" not in install

with tempfile.TemporaryDirectory(prefix="cortetsu-theme-test-") as tmp:
    root = Path(tmp)
    home = root / "home"
    config = home / ".config"
    data = home / ".local/share"
    cli = config / "caelestia/cli.json"
    cli.parent.mkdir(parents=True)
    original = {
        "theme": {
            "enableTerm": True,
            "enableHypr": True,
            "enableGtk": True,
            "enableQt": True,
            "enableDiscord": True,
            "postHook": "/example/preserved-hook",
        }
    }
    cli.write_text(json.dumps(original), encoding="utf-8")
    env = os.environ.copy()
    env.update({"HOME": str(home), "XDG_CONFIG_HOME": str(config), "XDG_DATA_HOME": str(data)})
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=env, check=True)
    migrated = json.loads(cli.read_text(encoding="utf-8"))
    for key in ("enableTerm", "enableHypr", "enableGtk", "enableQt"):
        assert migrated["theme"][key] is False
    assert migrated["theme"]["enableDiscord"] is True
    assert migrated["theme"]["postHook"] == "/example/preserved-hook"
    backups = list((data / "cortetsu/migrations").glob("*/theme-ownership/cli.json"))
    assert len(backups) == 1
    assert json.loads(backups[0].read_text(encoding="utf-8")) == original
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=env, check=True)
    assert len(list((data / "cortetsu/migrations").glob("*/theme-ownership/cli.json"))) == 1

print("PASS: ui.toml owns Cortetsu shell/Kitty/GTK/KDE theme outputs and safely disables Caelestia desktop mutation")
