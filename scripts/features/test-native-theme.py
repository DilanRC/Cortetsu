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
assert entries[".local/share/color-schemes/Cortetsu.colors"]["source"] == "dotfiles/generated/theme/home/.local/share/color-schemes/Cortetsu.colors"
assert ".config/kdeglobals" not in entries

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

kde = (repo / "dotfiles/generated/theme/home/.local/share/color-schemes/Cortetsu.colors").read_text(encoding="utf-8")
assert "Name=Cortetsu" in kde
assert "ColorScheme=" not in kde and "TerminalApplication=" not in kde
assert "[Colors:Window]" in kde and "[WM]" in kde
assert "Caelestia" not in kde

design = (repo / "cortetsu/modules/CortetsuDesign.js").read_text(encoding="utf-8")
assert 'var colorSumi = "#0B0D10"' in design
assert 'var colorVermillion = "#D64B32"' in design
assert "var motionFastMs = 120" in design
assert "var motionStandardMs = 180" in design
assert "var motionPanelMs = 240" in design
assert "var wallUtilitySurfaceRadius = 28" in design
assert "var wallUtilityOrbitMotionMs = 180" in design
assert "var wallUtilityOrbitTopGap = 32" in design
assert "var hoverScale = 1.025" in design

install = (repo / "scripts/install-cortetsu.sh").read_text(encoding="utf-8")
entrypoint = (repo / "scripts/cortetsu").read_text(encoding="utf-8")
assert "core/theme.py\" check" in install
assert "core/theme.py\" adopt" in install
assert install.index("core/theme.py\" adopt") < install.index("core/dotfiles.py\" apply")
assert 'export CORTETSU_DATA_ROOT="$DATA_ROOT"' in install
assert 'export CORTETSU_DATA_ROOT="$DATA_ROOT"' in entrypoint
assert entrypoint.index('python3 "$ROOT/core/theme.py" adopt --repo "$ROOT"') < entrypoint.index('python3 "$ROOT/core/dotfiles.py" "$action"')
assert "install-theme-bridge.py" not in install

with tempfile.TemporaryDirectory(prefix="cortetsu-theme-test-") as tmp:
    root = Path(tmp)
    home = root / "home"
    config = home / ".config"
    data = home / ".local/share"
    managed_kde = data / "cortetsu/dotfiles/builds/previous/home/.config/kdeglobals"
    managed_kde.parent.mkdir(parents=True)
    kde_original = (
        "[General]\nColorScheme=PreviousScheme\nTerminalApplication=kitty\n\n"
        "[KDE]\ncontrast=4\n\n[KFileDialog Settings]\n"
        "Show hidden files=true\n"
    )
    managed_kde.write_text(kde_original, encoding="utf-8")
    kdeglobals = config / "kdeglobals"
    config.mkdir(parents=True)
    kdeglobals.symlink_to(managed_kde)
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
    env.update({
        "HOME": str(home),
        "XDG_CONFIG_HOME": str(config),
        "XDG_DATA_HOME": str(data),
        "CORTETSU_DATA_ROOT": str(data / "cortetsu"),
    })
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=env, check=True)
    migrated = json.loads(cli.read_text(encoding="utf-8"))
    for key in ("enableTerm", "enableHypr", "enableGtk", "enableQt"):
        assert migrated["theme"][key] is False
    assert migrated["theme"]["enableDiscord"] is True
    assert migrated["theme"]["postHook"] == "/example/preserved-hook"
    backups = list((data / "cortetsu/migrations").glob("*/theme-ownership/cli.json"))
    assert len(backups) == 1
    assert json.loads(backups[0].read_text(encoding="utf-8")) == original
    assert not kdeglobals.is_symlink()
    migrated_kde = kdeglobals.read_text(encoding="utf-8")
    assert "ColorScheme=Cortetsu" in migrated_kde
    assert "TerminalApplication=kitty" in migrated_kde
    assert "[KFileDialog Settings]\nShow hidden files=true" in migrated_kde
    kde_backups = list((data / "cortetsu/migrations").glob("*/theme-ownership/kdeglobals"))
    assert len(kde_backups) == 1
    assert kde_backups[0].read_text(encoding="utf-8") == kde_original
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=env, check=True)
    assert len(list((data / "cortetsu/migrations").glob("*/theme-ownership/cli.json"))) == 1
    assert len(list((data / "cortetsu/migrations").glob("*/theme-ownership/kdeglobals"))) == 1

    fresh_home = root / "fresh-home"
    fresh_config = fresh_home / ".config"
    fresh_data = fresh_home / ".local/share"
    fresh_env = os.environ.copy()
    fresh_env.update({
        "HOME": str(fresh_home),
        "XDG_CONFIG_HOME": str(fresh_config),
        "XDG_DATA_HOME": str(fresh_data),
        "CORTETSU_DATA_ROOT": str(fresh_data / "cortetsu"),
    })
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=fresh_env, check=True)
    fresh_kde = fresh_config / "kdeglobals"
    assert fresh_kde.is_file() and not fresh_kde.is_symlink()
    assert "ColorScheme=Cortetsu" in fresh_kde.read_text(encoding="utf-8")
    assert "contrast=4" in fresh_kde.read_text(encoding="utf-8")
    assert not (fresh_data / "cortetsu/migrations").exists()

    no_cli_home = root / "no-cli-home"
    no_cli_config = no_cli_home / ".config"
    no_cli_data = no_cli_home / ".local/share"
    no_cli_target = no_cli_data / "cortetsu/dotfiles/builds/previous/home/.config/kdeglobals"
    no_cli_target.parent.mkdir(parents=True)
    no_cli_target.write_text("[General]\nColorScheme=Old\n", encoding="utf-8")
    no_cli_config.mkdir(parents=True)
    (no_cli_config / "kdeglobals").symlink_to(no_cli_target)
    no_cli_env = os.environ.copy()
    no_cli_env.update({
        "HOME": str(no_cli_home),
        "XDG_CONFIG_HOME": str(no_cli_config),
        "XDG_DATA_HOME": str(no_cli_data),
        "CORTETSU_DATA_ROOT": str(no_cli_data / "cortetsu"),
    })
    subprocess.run(["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)], env=no_cli_env, check=True)
    assert not (no_cli_config / "kdeglobals").is_symlink()
    assert "ColorScheme=Cortetsu" in (no_cli_config / "kdeglobals").read_text(encoding="utf-8")

    wrapper_home = root / "wrapper-home"
    wrapper_config = wrapper_home / ".config"
    wrapper_data_home = wrapper_home / ".local/share"
    wrapper_data = wrapper_data_home / "cortetsu"
    previous_kde = wrapper_data / "dotfiles/builds/previous/home/.config/kdeglobals"
    previous_kde.parent.mkdir(parents=True)
    previous_original = "[General]\nColorScheme=Previous\nTerminalApplication=kitty\n"
    previous_kde.write_text(previous_original, encoding="utf-8")
    wrapper_config.mkdir(parents=True)
    wrapper_link = wrapper_config / "kdeglobals"
    wrapper_link.symlink_to(previous_kde)
    mock_bin = root / "mock-bin"
    mock_bin.mkdir()
    mock_systemctl = mock_bin / "systemctl"
    mock_systemctl.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    mock_systemctl.chmod(0o755)
    wrapper_env = os.environ.copy()
    wrapper_env.update({
        "HOME": str(wrapper_home),
        "XDG_CONFIG_HOME": str(wrapper_config),
        "XDG_DATA_HOME": str(wrapper_data_home),
        "CORTETSU_DATA_ROOT": str(wrapper_data),
        "CORTETSU_REPO_ROOT": str(repo),
        "PATH": f"{mock_bin}:{os.environ['PATH']}",
    })
    wrapper_apply = subprocess.run(
        [str(repo / "scripts/cortetsu"), "dotfiles", "apply"],
        cwd=repo,
        env=wrapper_env,
        capture_output=True,
        text=True,
    )
    assert wrapper_apply.returncode == 0, wrapper_apply.stdout + wrapper_apply.stderr
    wrapper_kde = wrapper_config / "kdeglobals"
    assert wrapper_kde.is_file() and not wrapper_kde.is_symlink()
    wrapper_kde_text = wrapper_kde.read_text(encoding="utf-8")
    assert "ColorScheme=Cortetsu" in wrapper_kde_text
    assert "TerminalApplication=kitty" in wrapper_kde_text
    promoted = (wrapper_data / "dotfiles/current").resolve(strict=True)
    assert not (promoted / "home/.config/kdeglobals").exists()
    assert previous_kde.read_text(encoding="utf-8") == previous_original

    foreign_home = root / "foreign-home"
    foreign_config = foreign_home / ".config"
    foreign_data = foreign_home / ".local/share"
    foreign_config.mkdir(parents=True)
    foreign_target = root / "external-kdeglobals"
    foreign_original = "[General]\nColorScheme=UserScheme\n"
    foreign_target.write_text(foreign_original, encoding="utf-8")
    foreign_link = foreign_config / "kdeglobals"
    foreign_link.symlink_to(foreign_target)
    foreign_cli = foreign_config / "caelestia/cli.json"
    foreign_cli.parent.mkdir(parents=True)
    foreign_cli_original = json.dumps({"theme": {"enableTerm": True, "enableHypr": True}})
    foreign_cli.write_text(foreign_cli_original, encoding="utf-8")
    foreign_env = os.environ.copy()
    foreign_env.update({
        "HOME": str(foreign_home),
        "XDG_CONFIG_HOME": str(foreign_config),
        "XDG_DATA_HOME": str(foreign_data),
        "CORTETSU_DATA_ROOT": str(foreign_data / "cortetsu"),
    })
    rejected = subprocess.run(
        ["python3", str(repo / "core/theme.py"), "adopt", "--repo", str(repo)],
        env=foreign_env,
        capture_output=True,
        text=True,
    )
    assert rejected.returncode != 0
    assert foreign_link.is_symlink()
    assert foreign_target.read_text(encoding="utf-8") == foreign_original
    assert foreign_cli.read_text(encoding="utf-8") == foreign_cli_original
    assert not (foreign_data / "cortetsu/migrations").exists()

print("PASS: ui.toml owns Cortetsu shell/Kitty/GTK/KDE palette; kdeglobals stays editable and migrates safely")
