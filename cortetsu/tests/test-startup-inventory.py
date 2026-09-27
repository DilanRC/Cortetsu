#!/usr/bin/env python3
"""Temporary-home checks for startup inventory and reversible toggles."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import tempfile

SCRIPT = Path(__file__).resolve().parents[1] / "bin/cortetsu-startup"
loader = importlib.machinery.SourceFileLoader("cortetsu_startup", str(SCRIPT))
spec = importlib.util.spec_from_loader(loader.name, loader)
app = importlib.util.module_from_spec(spec)
loader.exec_module(app)


def put(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


with tempfile.TemporaryDirectory(prefix="cortetsu-startup-test-") as temp:
    base = Path(temp)
    home = base / "home"
    user_config = home / ".config"
    system_config = base / "etc/xdg"
    os.environ.update({
        "HOME": str(home), "XDG_CONFIG_HOME": str(user_config),
        "XDG_STATE_HOME": str(home / ".local/state"),
        "XDG_CONFIG_DIRS": str(system_config), "XDG_CURRENT_DESKTOP": "Hyprland",
    })
    put(user_config / "autostart/user.desktop", "[Desktop Entry]\nName=User App\nExec=user-app --background\nTryExec=/bin/sh\n")
    put(user_config / "autostart/hidden.desktop", "[Desktop Entry]\nName=Hidden\nExec=hidden\nHidden=true\n")
    put(user_config / "autostart/missing.desktop", "[Desktop Entry]\nName=Missing\nExec=missing\nTryExec=missing-cortetsu-test-binary\n")
    put(user_config / "autostart/only.desktop", "[Desktop Entry]\nName=Only GNOME\nExec=only\nOnlyShowIn=GNOME;\n")
    put(user_config / "autostart/not.desktop", "[Desktop Entry]\nName=Not Hyprland\nExec=not\nNotShowIn=Hyprland;\n")
    put(system_config / "autostart/global.desktop", "[Desktop Entry]\nName=Global\nExec=global\nTryExec=/bin/sh\n")
    put(user_config / "autostart/global.desktop", "[Desktop Entry]\nName=Global disabled\nExec=global\nHidden=true\n")
    put(user_config / "hypr/hyprland.lua", 'hl.on("hyprland.start", function()\n    hl.exec_cmd("user-app --background")\n    hl.exec_cmd("systemctl --user start enabled.service")\n    hl.exec_cmd("systemctl --user start work.service")\nend)\n')
    entries = {item["id"]: item for item in app.xdg_entries()}
    assert entries["xdg:user.desktop"]["configured"] is True
    assert entries["xdg:hidden.desktop"]["configured"] is False
    assert entries["xdg:missing.desktop"]["eligible"] is False
    assert entries["xdg:only.desktop"]["eligible"] is False
    assert entries["xdg:not.desktop"]["eligible"] is False
    assert entries["xdg:global.desktop"]["sourceType"] == "xdg-user"
    assert entries["xdg:global.desktop"]["configured"] is False
    assert app.duplicate_keys({"sourceType": "xdg-system", "configured": True, "eligible": False, "command": "user-app --background"}) == []
    lookup = app.user_unit_command_lookup([
        {"_unit": "audio.service", "_user": True, "command": "user-audio --start"},
        {"_unit": "audio.service", "_user": False, "command": "system-audio --start"},
    ])
    assert lookup["audio.service"] == [app.command_key("user-audio --start")]

    # A systemctl shim isolates all unit operations from the host.
    fake_bin = base / "bin"
    put(fake_bin / "systemctl", """#!/bin/sh
if [ "$1" = "--user" ]; then shift; fi
case "$1" in
  list-unit-files) cat "$UNIT_STATE" ;;
  list-units) printf 'transient.service loaded active running Temporary\\n' ;;
  show)
    shift
    for unit in "$@"; do
      case "$unit" in
        work.service)
          active=active
          [ ! -f "$STOPPED" ] || active=inactive
          printf 'Id=work.service\\nDescription=Worker\\nActiveState=%s\\nUnitFileState=disabled\\nFragmentPath=/tmp/work.service\\nWantedBy=default.target\\nExecStart={ path=user-app ; argv[]=user-app --background ; ignore_errors=no ; }\\n\\n' "$active"
          ;;
        enabled.service) printf 'Id=enabled.service\\nDescription=Enabled helper\\nActiveState=active\\nUnitFileState=enabled\\nExecStart={ path=user-app ; argv[]=user-app --background ; ignore_errors=no ; }\\n\\n' ;;
        clock.timer) printf 'Id=clock.timer\\nDescription=Clock\\nActiveState=inactive\\nUnitFileState=static\\n\\n' ;;
        wait.socket) printf 'Id=wait.socket\\nDescription=Socket\\nActiveState=inactive\\nUnitFileState=disabled\\n\\n' ;;
        generated.service) printf 'Id=generated.service\\nDescription=Generated\\nActiveState=inactive\\nUnitFileState=generated\\n\\n' ;;
        alias.service) printf 'Id=alias.service\\nDescription=Alias\\nActiveState=inactive\\nUnitFileState=alias\\n\\n' ;;
        indirect.service) printf 'Id=indirect.service\\nDescription=Indirect\\nActiveState=inactive\\nUnitFileState=indirect\\n\\n' ;;
        transient.service) printf 'Id=transient.service\\nDescription=Transient\\nActiveState=active\\nUnitFileState=transient\\n\\n' ;;
      esac
    done
    ;;
  enable) sed -i 's/work.service disabled/work.service enabled/' "$UNIT_STATE" ;;
  disable) sed -i 's/work.service enabled/work.service disabled/' "$UNIT_STATE" ;;
  stop) touch "$STOPPED" ;;
esac
""")

    (fake_bin / "systemctl").chmod(0o755)
    state = base / "units"
    state.write_text("work.service disabled enabled\nenabled.service enabled enabled\nclock.timer static -\nwait.socket disabled enabled\ngenerated.service generated -\nalias.service alias -\nindirect.service indirect -\n", encoding="utf-8")
    env_path = os.environ.get("PATH", "")
    os.environ["PATH"] = str(fake_bin) + os.pathsep + env_path
    os.environ["UNIT_STATE"] = str(state)
    stopped = base / "stopped"
    os.environ["STOPPED"] = str(stopped)
    outside = base / "outside.desktop"
    put(outside, "[Desktop Entry]\nName=Outside\nExec=outside\n")
    os.symlink(outside, user_config / "autostart/link.desktop")
    try:
        app.action("xdg:link.desktop", "disable")
        raise AssertionError("symlinked desktop file must be rejected")
    except ValueError as error:
        assert "enlaces simbólicos" in str(error)
    # Enabling and disabling a global entry uses a user override only.
    (user_config / "autostart/global.desktop").unlink()
    result = app.action("xdg:global.desktop", "disable")
    assert result["ok"] and result["entry"]["configured"] is False
    assert (system_config / "autostart/global.desktop").read_text().find("Hidden=") == -1
    app.action("xdg:global.desktop", "enable")
    assert {item["id"]: item for item in app.xdg_entries()}["xdg:global.desktop"]["configured"] is True
    units = {item["id"]: item for item in app.systemd_entries(True)}
    assert units["user-unit:work.service"]["configured"] is False
    assert units["user-unit:work.service"]["running"] is True
    assert units["user-unit:clock.timer"]["modifiable"] is False
    assert units["user-unit:wait.socket"]["modifiable"] is True
    assert units["user-unit:generated.service"]["modifiable"] is False
    assert units["user-unit:alias.service"]["modifiable"] is False
    assert units["user-unit:indirect.service"]["modifiable"] is False
    assert units["user-unit:transient.service"]["unitState"] == "transient"
    assert units["user-unit:transient.service"]["running"] is True
    assert units["user-unit:transient.service"]["modifiable"] is False
    assert len([item for item in units.values() if item["id"] == "user-unit:work.service"]) == 1
    scanned = {item["id"]: item for item in app.scan()}
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":2"]["command"] == "user-app --background"
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":2"]["modifiable"] is False
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":3"]["duplicateCount"] == 5
    assert scanned["hyprland:" + str(home / ".config/hypr/hyprland.lua") + ":4"]["duplicateCount"] == 5
    assert scanned["user-unit:work.service"]["duplicateCount"] == 0
    assert scanned["user-unit:enabled.service"]["duplicateCount"] == 5
    assert scanned["xdg:user.desktop"]["duplicateCount"] == 5
    assert all(not item["modifiable"] for item in app.systemd_entries(False))
    stopped_result = app.action("user-unit:work.service", "stop")
    assert stopped_result["ok"] and stopped_result["entry"]["running"] is False
    assert stopped_result["entry"]["configured"] is False
    app.action("user-unit:work.service", "enable")
    assert {item["id"]: item for item in app.systemd_entries(True)}["user-unit:work.service"]["configured"] is True
    app.action("user-unit:work.service", "disable")
    assert {item["id"]: item for item in app.systemd_entries(True)}["user-unit:work.service"]["configured"] is False
    changes = [json.loads(line) for line in (home / ".local/state/cortetsu/startup/changes.jsonl").read_text().splitlines()]
    assert any(change.get("action") == "stop" and change.get("oldState") == "running" and change.get("newState") == "stopped" for change in changes)

print("PASS: XDG overrides and user systemd toggles use isolated fixtures")
