#!/usr/bin/env python3
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCRIPT = REPO / "core/shell_lifecycle.py"
UNIT = REPO / "config/systemd/user/cortetsu-shell.service"
INSTALLER = REPO / "scripts/install-cortetsu.sh"

unit_text = UNIT.read_text(encoding="utf-8")
assert "Type=simple" in unit_text
exec_start = next(line for line in unit_text.splitlines() if line.startswith("ExecStart="))
assert "/usr/bin/qs" in exec_start
assert " -n" in exec_start
assert " -d" not in exec_start and "--daemonize" not in exec_start, (
    "systemd must own the foreground Quickshell process; daemonizing makes Type=simple go inactive"
)

installer_text = INSTALLER.read_text(encoding="utf-8")
assert "is-enabled --quiet cortetsu-shell.service" in installer_text
assert "no se reinicia automáticamente" in installer_text
assert "cortetsu shell reload" in installer_text
assert "CORTETSU_RESTART_SHELL=1 cortetsu shell restart" in installer_text
assert "systemctl --user restart cortetsu-shell.service" not in installer_text
cli_text = (REPO / "scripts/cortetsu").read_text(encoding="utf-8")
assert "shell_restart_allowed" in cli_text
assert "pgrep -x ChatGPT" in cli_text
assert 'CORTETSU_RESTART_SHELL:-0' in cli_text
assert "shell_reload()" in cli_text
assert 'qs ipc --pid "$pid" call cortetsu-shell reload' in cli_text
assert '[[ "$after" == "$pid" ]]' in cli_text
shell_text = (REPO / "cortetsu/modules/ShellLifecycle.qml").read_text(encoding="utf-8")
assert 'target: "cortetsu-shell"' in shell_text
assert "Quickshell.reload(false);" in shell_text

with tempfile.TemporaryDirectory(prefix="cortetsu-shell-lifecycle-") as tmp:
    root = Path(tmp)
    home = root / "home"
    data = root / "data"
    hypr = home / ".config/hypr/hyprland"
    hypr.mkdir(parents=True)

    execs = hypr / "execs.lua"
    keybinds = hypr / "keybinds.lua"
    stale_backup = hypr / "keybinds.lua.bak"

    execs.write_text(
        'hl.exec_cmd("caelestia shell -d")\n'
        'hl.exec_cmd(os.getenv("HOME") .. "/.local/bin/caelestia-wallpaper-color-daemon")\n',
        encoding="utf-8",
    )
    keybinds.write_text(
        'hl.dispatch(hl.dsp.exec_cmd("caelestia shell -d"))\n'
        'create_bind("CTRL + SUPER + SHIFT + R", hl.dsp.exec_cmd("qs -c caelestia kill"), release)\n'
        'hl.dsp.exec_cmd("qs -c caelestia kill; sleep .1; caelestia shell -d")\n'
        'create_bind(vars.kbScreenshot, hl.dsp.exec_cmd("caelestia screenshot"), locked)\n',
        encoding="utf-8",
    )
    stale_backup.write_text('caelestia shell -d\n', encoding="utf-8")

    env = os.environ.copy()
    env.update(HOME=str(home), CORTETSU_DATA_ROOT=str(data))

    scan = subprocess.run(
        ["python3", str(SCRIPT), "scan", "--home", str(home)],
        cwd=REPO,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    assert scan.returncode == 1
    assert "execs.lua" in scan.stdout and "keybinds.lua" in scan.stdout

    migrated = subprocess.run(
        ["python3", str(SCRIPT), "migrate", "--home", str(home)],
        cwd=REPO,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    assert "MIGRATED lifecycle=" in migrated.stdout
    assert "BACKUP lifecycle=" in migrated.stdout

    execs_text = execs.read_text(encoding="utf-8")
    keybinds_text = keybinds.read_text(encoding="utf-8")
    assert "caelestia shell -d" not in execs_text
    assert "caelestia shell -d" not in keybinds_text
    assert "qs -c caelestia kill" not in keybinds_text
    assert "systemctl --user start cortetsu-shell.service" in execs_text
    assert "systemctl --user start cortetsu-shell.service" in keybinds_text
    assert "systemctl --user stop cortetsu-shell.service" in keybinds_text
    assert "systemctl --user restart cortetsu-shell.service" in keybinds_text
    assert "caelestia screenshot" not in keybinds_text
    assert "cortetsu screenshot" in keybinds_text
    assert stale_backup.read_text(encoding="utf-8") == "caelestia shell -d\n"

    backups = list((data / "migrations").glob("*/hypr-shell-lifecycle/.config/hypr/hyprland/execs.lua"))
    assert backups, "expected a backup of active Hyprland lifecycle config"
    assert "caelestia shell -d" in backups[0].read_text(encoding="utf-8")

    verify = subprocess.run(
        ["python3", str(SCRIPT), "verify", "--home", str(home)],
        cwd=REPO,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    assert "PASS: Hyprland shell lifecycle is systemd-owned" in verify.stdout

    second = subprocess.run(
        ["python3", str(SCRIPT), "migrate", "--home", str(home)],
        cwd=REPO,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=True,
    )
    assert "already reconciled" in second.stdout

print("PASS: systemd owns foreground Quickshell; Hyprland lifecycle migration is backed up and idempotent")
