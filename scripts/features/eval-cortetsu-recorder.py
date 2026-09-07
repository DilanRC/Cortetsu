#!/usr/bin/env python3
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
source = (repo / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")

criteria = {
    "plain recording bind": 'create_bind(vars.kbRecord, hl.dsp.exec_cmd("cortetsu-record start"))',
    "sound recording bind": 'create_bind(vars.kbRecordSound, hl.dsp.exec_cmd("cortetsu-record start -s"))',
    "region recording bind": 'create_bind(vars.kbRecordRegion, hl.dsp.exec_cmd("cortetsu-record start -r"))',
    "no legacy recording command": "caelestia record" not in source,
}
passed = sum(bool(value) for value in criteria.values())
print(f"Cortetsu recorder keybind eval: {passed}/{len(criteria)} ({passed / len(criteria):.0%})")
if passed != len(criteria):
    raise SystemExit("FAIL: " + ", ".join(name for name, value in criteria.items() if not value))
