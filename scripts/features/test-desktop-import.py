#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "core/import_desktop.py"


def run(args: list[str], *, repo: Path, home: Path, check: bool = False) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env["HOME"] = str(home)
    return subprocess.run(
        ["python3", str(SCRIPT), *args, "--repo", str(repo), "--home", str(home)],
        cwd=repo,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=check,
    )


with tempfile.TemporaryDirectory(prefix="cortetsu-desktop-import-") as tmp:
    root = Path(tmp)
    repo = root / "repo"
    home = root / "home"
    (repo / "dotfiles").mkdir(parents=True)
    home.mkdir()

    (repo / "dotfiles/manifest.toml").write_text(
        'schema = 1\n\n[defaults]\nprofile = "personal"\n',
        encoding="utf-8",
    )
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.email", "cortetsu-test@example.invalid"], check=True)
    subprocess.run(["git", "-C", str(repo), "config", "user.name", "Cortetsu Test"], check=True)
    subprocess.run(["git", "-C", str(repo), "add", "dotfiles/manifest.toml"], check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-qm", "initial"], check=True)

    kitty = home / ".config/kitty"
    gtk3 = home / ".config/gtk-3.0"
    qt6 = home / ".config/qt6ct"
    kitty.mkdir(parents=True)
    gtk3.mkdir(parents=True)
    qt6.mkdir(parents=True)

    (kitty / "kitty.conf").write_text(
        "include caelestia-theme.conf\n"
        "include ~/.local/state/caelestia/theme/kitty-caerice.conf\n"
        "font_size 11\ninclude theme.conf\n",
        encoding="utf-8",
    )
    (kitty / "caelestia-theme.conf").write_text("background #000000\n", encoding="utf-8")
    (kitty / "cortetsu-theme.conf").write_text("background #111111\n", encoding="utf-8")
    (kitty / "old.conf.bak").write_text("old\n", encoding="utf-8")
    os.symlink("kitty.conf", kitty / "theme.conf")
    (home / ".zshrc").write_text("export EDITOR=nvim\n", encoding="utf-8")
    (gtk3 / "settings.ini").write_text("[Settings]\ngtk-theme-name=Adwaita\n", encoding="utf-8")
    (gtk3 / "gtk.css").write_text(
        "@define-color accent_color #c6c6c6;\n@import \"thunar.css\";\n",
        encoding="utf-8",
    )
    (gtk3 / "cortetsu-colors.css").write_text("@define-color accent_color #D64B32;\n", encoding="utf-8")
    (home / ".config/kdeglobals").write_text("[General]\nColorScheme=Caelestia\n", encoding="utf-8")
    (qt6 / "qt6ct.conf").write_text("[Appearance]\nstyle=kvantum\n", encoding="utf-8")
    sensitive = kitty / "private.conf"
    sensitive.write_text("api_key = do-not-import\n", encoding="utf-8")

    (repo / "UNRELATED").write_text("leave me alone\n", encoding="utf-8")

    blocked = run(["plan"], repo=repo, home=home)
    assert blocked.returncode == 2, blocked.stdout
    assert "BLOCKED" in blocked.stdout and "private.conf" in blocked.stdout

    refused = run(["apply"], repo=repo, home=home)
    assert refused.returncode == 1, refused.stdout
    assert "posibles secretos" in refused.stdout
    assert not (repo / "dotfiles/imported/desktop").exists()

    sensitive.unlink()
    plan = run(["plan"], repo=repo, home=home, check=True)
    assert "[kitty]" in plan.stdout
    assert "[zsh" in plan.stdout
    assert "[gtk" in plan.stdout
    assert "[qt" in plan.stdout
    assert "old.conf.bak" in plan.stdout and "backup/temp" in plan.stdout
    assert "theme.conf" in plan.stdout and "symlink" in plan.stdout
    assert "caelestia-theme.conf" in plan.stdout and "theme-owned" in plan.stdout
    assert "cortetsu-theme.conf" in plan.stdout and "theme-owned" in plan.stdout
    assert "cortetsu-colors.css" in plan.stdout and "theme-owned" in plan.stdout
    assert "kdeglobals" in plan.stdout and "user-owned" in plan.stdout

    applied = run(["apply", "--commit"], repo=repo, home=home, check=True)
    assert "IMPORTED desktop=" in applied.stdout
    assert "COMMIT created=desktop import" in applied.stdout

    manifest = (repo / "dotfiles/manifest.toml").read_text(encoding="utf-8")
    assert "# BEGIN CORTETSU DESKTOP IMPORT" in manifest
    assert '.config/kitty/kitty.conf' in manifest
    assert '.zshrc' in manifest
    assert '.config/gtk-3.0/settings.ini' in manifest
    assert '.config/qt6ct/qt6ct.conf' in manifest
    assert '.config/kdeglobals' not in manifest
    assert '.config/kitty/caelestia-theme.conf' not in manifest
    assert '.config/kitty/cortetsu-theme.conf' not in manifest
    assert 'tags = ["terminal"]' in manifest
    assert 'tags = ["user-shell"]' in manifest
    assert 'tags = ["toolkit"]' in manifest
    assert "old.conf.bak" not in manifest
    assert "theme.conf" not in manifest

    imported = repo / "dotfiles/imported/desktop/home"
    imported_kitty = (imported / ".config/kitty/kitty.conf").read_text(encoding="utf-8")
    assert imported_kitty.startswith("include cortetsu-theme.conf\n")
    assert "state/caelestia/theme" not in imported_kitty
    assert "include caelestia-theme.conf" not in imported_kitty
    imported_gtk = (imported / ".config/gtk-3.0/gtk.css").read_text(encoding="utf-8")
    assert imported_gtk.startswith('@import "cortetsu-colors.css";\n')
    assert "@define-color accent_color #c6c6c6" not in imported_gtk
    assert (imported / ".zshrc").is_file()
    assert not (imported / ".config/kitty/old.conf.bak").exists()
    assert not (imported / ".config/kitty/theme.conf").exists()
    assert not (imported / ".config/kitty/caelestia-theme.conf").exists()
    assert not (imported / ".config/kdeglobals").exists()

    changed = subprocess.check_output(
        ["git", "-C", str(repo), "show", "--pretty=", "--name-only", "HEAD"], text=True
    )
    assert "dotfiles/manifest.toml" in changed
    assert "dotfiles/imported/desktop" in changed
    assert "UNRELATED" not in changed
    status = subprocess.check_output(["git", "-C", str(repo), "status", "--porcelain"], text=True)
    assert "?? UNRELATED" in status

    second = run(["apply", "--commit"], repo=repo, home=home, check=True)
    assert "COMMIT skipped=no changes" in second.stdout

print("PASS: desktop importer snapshots behaviour, blocks secrets, isolates staging and preserves Cortetsu native theme ownership")
