#!/usr/bin/env python3
"""F0 inventory: every first-party entrypoint (by extension AND shebang) with
LOC, who invokes it (QML/units/CLI/scripts), imports and external commands.
Usage: python3 -I inventory.py <repo> > inventory.json   (read-only)"""
import json, os, re, subprocess, sys
from pathlib import Path
repo = Path(sys.argv[1]).resolve()
files = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True, check=True).stdout.split()
def lang(f):
    p = repo / f
    if not p.is_file(): return None
    ext = p.suffix
    if ext in (".py", ".qml", ".lua", ".rs", ".go", ".sh"): return ext[1:]
    if ext == "" :
        head = p.open("rb").read(100).split(b"\n")[0].decode(errors="replace")
        if head.startswith("#!"):
            return "py" if "python" in head else "sh" if re.search(r"\b(ba)?sh\b", head) else "other"
    if p.name in ("Cargo.toml",): return "cargo"
    if f.startswith("config/systemd/") : return "unit"
    return None
texts = {}
for f in files:
    p = repo / f
    if p.is_file() and p.suffix in (".qml", ".py", ".sh", ".lua", ".rs", ".service", ".js", ".toml", ".yml", "") :
        try: texts[f] = p.read_text(errors="replace")
        except Exception: pass
out = []
CMDS = ["hyprctl", "nmcli", "bluetoothctl", "busctl", "gdbus", "powerprofilesctl", "systemctl", "notify-send", "gpu-screen-recorder", "wpctl", "pactl", "secret-tool", "loginctl", "brightnessctl", "qs", "nvidia-smi", "matugen", "swww", "awww", "curl"]
for f in files:
    l = lang(f)
    if not l: continue
    t = texts.get(f, "")
    name = Path(f).name
    stem = Path(f).stem
    entry = {"path": f, "lang": l, "loc": t.count("\n")}
    if l == "py":
        entry["imports"] = sorted(set(re.findall(r"^\s*(?:from|import)\s+([A-Za-z_][\w]*)", t, re.M)))
    if l in ("py", "sh", "rs"):
        entry["external_cmds"] = sorted(c for c in CMDS if re.search(r"[\"'\s\[(]%s[\"'\s,)]" % re.escape(c), t))
    if f.startswith(("cortetsu/bin/", "core/", "scripts/cortetsu", "cortetsu/services/", "config/systemd")) or l in ("unit", "cargo"):
        key = name if f.startswith("cortetsu/bin/") else stem
        refs = sorted(g for g, tx in texts.items() if g != f and key in tx and not g.startswith(("docs/", "graphify")))
        entry["referenced_by"] = {
            "qml": [r for r in refs if r.endswith(".qml")],
            "units": [r for r in refs if r.startswith("config/systemd")],
            "cli_or_core": [r for r in refs if r.startswith(("scripts/cortetsu", "core/", "scripts/lib"))],
            "tests": len([r for r in refs if "/test" in r or "/eval" in r or "tests/" in r]),
            "other": [r for r in refs if not (r.endswith(".qml") or r.startswith(("config/systemd", "scripts/cortetsu", "core/", "scripts/lib")) or "/test" in r or "tests/" in r or "/eval" in r)][:8],
        }
    out.append(entry)
json.dump({"repo": str(repo), "head": subprocess.run(["git","-C",repo,"rev-parse","HEAD"],capture_output=True,text=True).stdout.strip(), "entries": out}, sys.stdout, indent=1)
