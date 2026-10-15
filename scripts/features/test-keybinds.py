#!/usr/bin/env python3
"""cortetsu-keybinds without Hyprland: validation, store, compile, rollback.

A fake hyprctl applies the store the way hyprland.lua does (variables, then
unbind, then binds) and reports binds with their descriptions.
test-keybind-editor-runtime.py runs the same flows against the real loader.
"""
from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "cortetsu/bin/cortetsu-keybinds"

FAKE_HYPRCTL = r'''#!/usr/bin/env python3
import json, os, re, sys
from pathlib import Path
home = Path(os.environ["HOME"])
if os.environ.get("FAKE_RELOAD_FAILS") and sys.argv[1:] == ["reload"]:
    sys.exit(1)
if sys.argv[1:] == ["reload"]:
    sys.exit(0)
assert sys.argv[1:] == ["binds", "-j"], sys.argv
bits = {"SHIFT": 1, "CTRL": 4, "ALT": 8, "SUPER": 64}
def entry(chord, description):
    *mods, key = [part.strip() for part in chord.split("+")]
    return {"modmask": sum(bits[m.upper()] for m in mods), "key": key, "description": description}
text = (home / ".config/hypr/variables.lua").read_text()
variables = {m.group(1): re.findall(r'"([^"]*)"', m.group(2)) for m in re.finditer(r'(kb\w+)\s*=\s*(\{[^}]*\}|"[^"]*")', text)}
store_path = home / ".config/cortetsu/keybinds.json"
store = json.loads(store_path.read_text()) if store_path.exists() else {}
variables.update(store.get("variables", {}))
binds = [entry(chord, "cortetsu:" + name) for name, chords in variables.items() for chord in chords]
user = (home / ".config/hypr/hypr-user.lua").read_text()
binds += [entry(chord, "") for chord in re.findall(r'hl\.bind\(\s*"([^"]+)"', user)]
gone = {(b["modmask"], b["key"].upper()) for b in map(lambda c: entry(c, ""), store.get("unbind", []))}
binds = [b for b in binds if (b["modmask"], b["key"].upper()) not in gone]
binds += [entry(b["chord"], "cortetsu-keybinds:" + b["id"]) for b in store.get("binds", [])]
print(json.dumps(binds))
'''

VARIABLES = '''return {
    browser = "firefox",
    -- kbRetired = "SUPER + Z",
    kbBrowser = "SUPER + W",
    kbNextWs = { "SUPER + Right", "SUPER + Page_Down" },
    kbGoToWs = "SUPER",
    kbUnused = "SUPER + U",
}
'''

USER = '''-- Cortetsu app shortcut: Spotify (spotify)
hl.bind(
    "SUPER + O",
    hl.dsp.exec_cmd([[spotify]])
)

hl.bind("SUPER + G", function() hl.dispatch(hl.dsp.exec_cmd("github-desktop")) end)

hl.bind("SUPER + J", hl.dsp.exec_cmd("xdg-open ~/Música/canción.flac"))
'''


def run(home: Path, *args: str, **env: str) -> dict:
    result = subprocess.run([sys.executable, str(HELPER), *args], text=True, capture_output=True,
                            env=dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                                     CORTETSU_HYPRCTL=str(home / "hyprctl"), **env), timeout=30)
    return json.loads(result.stdout)


def by_id(home: Path) -> dict:
    return {item["id"]: item for item in run(home, "list")["bindings"]}


with tempfile.TemporaryDirectory(prefix="cortetsu-keybinds-") as temporary:
    home = Path(temporary)
    hypr = home / ".config/hypr"
    hypr.mkdir(parents=True)
    generation = home / "generation"
    generation.mkdir()
    (generation / "variables.lua").write_text(VARIABLES)
    (generation / "hypr-user.lua").write_text(USER)
    (generation / "hyprland").mkdir()
    (generation / "hyprland/keybinds.lua").write_text(
        'create_bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))\n'
        'create_bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }))\n')
    for name in ("variables.lua", "hypr-user.lua", "hyprland"):
        (hypr / name).symlink_to(generation / name)
    fake = home / "hyprctl"
    fake.write_text(FAKE_HYPRCTL)
    fake.chmod(0o755)
    sealed = {name: (generation / name).read_text() for name in ("variables.lua", "hypr-user.lua")}
    store = home / ".config/cortetsu/keybinds.json"

    items = by_id(home)
    assert items["var:kbBrowser:0"]["command"] == "firefox" and items["var:kbBrowser:0"]["origin"] == "default"
    assert "var:kbGoToWs:0" not in items, "a modifier prefix is not a shortcut"
    assert not any(item["id"].startswith(("var:kbRetired", "var:kbUnused")) for item in items.values()), \
        "a comment or an unused variable is not a bind"
    music = next(item for item in items.values() if item["chord"] == "SUPER + J")
    assert music["command"] == "xdg-open ~/Música/canción.flac", music["command"]
    spotify = next(item for item in items.values() if item.get("appName") == "Spotify")
    lua = next(item for item in items.values() if item["chord"] == "SUPER + G")
    assert spotify["editable"] and not lua["editable"] and "hypr-user.lua" in lua["note"]

    # Chord validation runs before anything is written.
    for chord, words in (("CTRL + End", "aplicaciones"), ("CTRL + Down", "aplicaciones"), ("F5", "tecla sola"),
                         ("SUPER + Ñ", "no es una tecla"), ("HYPER + A", "no es un modificador"),
                         ("SUPER + O", "ya es"), ("SUPER + G", "ya es")):
        result = run(home, "set", "var:kbBrowser:0", chord)
        assert not result["ok"] and words in result["error"], (chord, result)
    assert not store.exists()
    for chord in ("XF86Calculator", "XF86Launch2", "SUPER + SHIFT + F23", "CTRL + ALT + T", "SUPER + KP_1", "F13"):
        assert run(home, "set", "var:kbBrowser:0", chord)["ok"], chord
    assert by_id(home)["var:kbBrowser:0"]["chord"] == "F13"

    # The store is the only file written; the compiled twin is data-only Lua.
    assert run(home, "set", "var:kbNextWs:1", "SUPER + CTRL + Right")["ok"]
    assert json.loads(store.read_text())["variables"]["kbNextWs"] == ["SUPER + Right", "SUPER + CTRL + Right"]
    compiled = (hypr / "cortetsu-keybinds.lua").read_text()
    assert "kbNextWs = { \"SUPER + Right\", \"SUPER + CTRL + Right\" }" in compiled and "function" not in compiled
    if shutil.which("luac"):
        subprocess.run(["luac", "-p", str(hypr / "cortetsu-keybinds.lua")], check=True)

    # hypr-user binds move through unbind + bind, never by editing the file.
    assert run(home, "set", spotify["id"], "SUPER + ALT + O")["ok"]
    stored = json.loads(store.read_text())
    assert stored["unbind"] == ["SUPER + O"] and stored["binds"][0]["exec"] == "spotify"
    assert not by_id(home)[spotify["id"]]["active"]
    assert run(home, "reset", spotify["id"])["ok"]
    assert json.loads(store.read_text())["binds"] == [] and by_id(home)[spotify["id"]]["active"]

    # Accented commands survive the move to the edit layer.
    assert run(home, "set", music["id"], "SUPER + ALT + J")["ok"]
    assert json.loads(store.read_text())["binds"][0]["exec"] == "xdg-open ~/Música/canción.flac"
    assert run(home, "reset", music["id"])["ok"] and json.loads(store.read_text())["binds"] == []

    # Delete, then reset, for a variable; an app goes away entirely.
    assert run(home, "delete", "var:kbNextWs:0")["ok"] and run(home, "delete", "var:kbNextWs:0")["ok"]
    assert "var:kbNextWs:-" in by_id(home)
    assert run(home, "reset", "var:kbNextWs:-")["ok"] and by_id(home)["var:kbNextWs:1"]["chord"] == "SUPER + Page_Down"
    assert run(home, "add-app", "org.example.App", "Example", "example --open %U", "SUPER + ALT + E")["ok"]
    app = next(item for item in by_id(home).values() if item.get("appId") == "org.example.App")
    assert app["command"] == "example --open"
    assert run(home, "delete", app["id"])["ok"] and app["id"] not in by_id(home)

    # A reload that fails leaves both files as they were.
    before = (store.read_text(), (hypr / "cortetsu-keybinds.lua").read_text())
    failed = run(home, "set", "var:kbBrowser:0", "SUPER + ALT + B", FAKE_RELOAD_FAILS="1")
    assert not failed["ok"] and (store.read_text(), (hypr / "cortetsu-keybinds.lua").read_text()) == before

    # Neither generation file was touched, and their symlinks are intact.
    assert all((generation / name).read_text() == text for name, text in sealed.items())
    assert (hypr / "variables.lua").is_symlink() and (hypr / "hypr-user.lua").is_symlink()
print("PASS: keybind helper validates chords, edits only its store, compiles data-only Lua and rolls back")
