#!/usr/bin/env python3
"""scope: application shortcuts limited to some keyboards.

Two binds may share a chord when no keyboard fires both; the store keeps the
scope, the compiled Lua passes it as Hyprland's `device` flag and a change is
verified against what the loaded hyprland.lua reports through `repl`, rolled
back when Hyprland does not hold it. Same fixture as test-keybinds.py; the
fake hyprctl also lists keyboards and answers the scope report.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent / "lib"))
import keybinds_helper  # noqa: E402

SOURCE = (HERE / "test-keybinds.py").read_text(encoding="utf-8")
BASE_HYPRCTL = SOURCE.split("FAKE_HYPRCTL = r'''", 1)[1].split("'''", 1)[0]
VARIABLES = SOURCE.split("VARIABLES = '''", 1)[1].split("'''", 1)[0]
USER = SOURCE.split("USER = '''", 1)[1].split("'''", 1)[0]
HELPER = keybinds_helper.command()

# FAKE_LOADER=old: a hyprland.lua without the report. FAKE_LOADER=global:
# one that reports every bind as global, as if it ignored the field.
EXTRA = r'''
if sys.argv[1:] == ["devices", "-j"]:
    print(json.dumps({"keyboards": [{"name": "kb-a"}, {"name": "kb-b"}, {"name": "kb-c"}]}))
    sys.exit(0)
if sys.argv[1] == "repl":
    loader = os.environ.get("FAKE_LOADER", "")
    if loader == "old":
        print("N")
        sys.exit(0)
    store_path = home / ".config/cortetsu/keybinds.json"
    stored = json.loads(store_path.read_text()) if store_path.exists() else {}
    lines = []
    for bind in stored.get("binds", []):
        devices = {} if loader == "global" else bind.get("devices") or {}
        lines.append("\t".join([bind["id"], "true" if devices.get("only") else "false", *devices.get("names", [])]))
    print("S=" + "\n".join(lines))
    sys.exit(0)
'''
FAKE_HYPRCTL = BASE_HYPRCTL.replace('assert sys.argv[1:] == ["binds", "-j"]', EXTRA + 'assert sys.argv[1:] == ["binds", "-j"]')
assert FAKE_HYPRCTL != BASE_HYPRCTL

with tempfile.TemporaryDirectory(prefix="cortetsu-keybinds-scope-") as temporary:
    home = Path(temporary)
    hypr = home / ".config/hypr"
    (hypr / "hyprland").mkdir(parents=True)
    (hypr / "variables.lua").write_text(VARIABLES)
    (hypr / "hypr-user.lua").write_text(USER)
    (hypr / "hyprland/keybinds.lua").write_text('create_bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))\n')
    fake = home / "hyprctl"
    fake.write_text(FAKE_HYPRCTL)
    fake.chmod(0o755)
    store = home / ".config/cortetsu/keybinds.json"
    compiled = hypr / "cortetsu-keybinds.lua"

    def run(*args: str, **env: str) -> dict:
        result = subprocess.run([*HELPER, *args], text=True, capture_output=True, timeout=30,
                                env=dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                                         CORTETSU_HYPRCTL=str(fake), **env))
        return json.loads(result.stdout)

    def rows() -> dict:
        # `bindings`, not `list`: protocol 1 rows stay those of the Python helper.
        listing = run("bindings")
        assert all("scopable" not in item for item in run("list")["bindings"])
        return {item["id"]: item for item in listing["bindings"]}

    def app(app_id: str) -> dict:
        return next(item for item in rows().values() if item.get("appId") == app_id)

    assert run("add-app", "org.example.Calc", "Calc", "calc", "SUPER + ALT + E")["ok"]
    assert run("add-app", "org.example.Notes", "Notes", "notes", "SUPER + ALT + N")["ok"]
    calc, notes = app("org.example.Calc"), app("org.example.Notes")
    assert calc["scopable"] and "devices" not in calc, calc

    # Only the editor's own binds take a scope; the base layers are Lua.
    base = run("scope", "var:kbBrowser:0", "only", "kb-a")
    assert not base["ok"] and "configuración base" in base["error"], base
    spotify = next(item for item in rows().values() if item.get("appName") == "Spotify")
    assert not spotify["scopable"] and not run("scope", spotify["id"], "only", "kb-a")["ok"]
    for args, words in ((("only",), "al menos un teclado"), (("all", "kb-a"), "no lleva"),
                        (("some", "kb-a"), "Modo desconocido"), (("only", "kb-x"), "kb-x")):
        refused = run("scope", calc["id"], *args)
        assert not refused["ok"] and words in refused["error"], (args, refused)
    assert "devices" not in json.loads(store.read_text())["binds"][0]

    # Limited, stored, compiled for Hyprland and verified.
    limited = run("scope", calc["id"], "only", "kb-a")
    assert limited["ok"] and limited["devices"] == {"only": True, "names": ["kb-a"]}, limited
    assert "solo en kb-a" in limited["message"], limited
    assert 'device = { inclusive = true, list = { "kb-a" } }' in compiled.read_text()
    assert app("org.example.Calc")["devices"] == {"only": True, "names": ["kb-a"]}

    # A second app on the same chord: refused while the keyboards meet.
    taken = run("set", notes["id"], "SUPER + ALT + E")
    assert not taken["ok"] and "ya es «Calc»" in taken["error"], taken
    assert run("scope", notes["id"], "only", "kb-b", "kb-c")["ok"]
    assert run("set", notes["id"], "SUPER + ALT + E")["ok"], "disjoint keyboards share a chord"
    calc, notes = app("org.example.Calc"), app("org.example.Notes")
    assert calc["conflicts"] == [] and notes["conflicts"] == [], (calc, notes)
    assert notes["devices"] == {"only": True, "names": ["kb-b", "kb-c"]}, "set keeps the scope"

    # Widening one of them onto the other's keyboard is refused.
    for args in (("all",), ("except", "kb-b"), ("only", "kb-a", "kb-b")):
        widened = run("scope", calc["id"], *args)
        assert not widened["ok"] and "ya es «Notes»" in widened["error"], (args, widened)
    assert run("scope", calc["id"], "except", "kb-b", "kb-c")["ok"], "except b, c is disjoint from only b, c"
    assert app("org.example.Calc")["devices"] == {"only": False, "names": ["kb-b", "kb-c"]}
    before = store.read_text()

    # Hyprland must hold the scope; otherwise the change is rolled back.
    for loader, words in (("old", "actualiza hyprland.lua"), ("global", "Hyprland no tiene")):
        failed = run("scope", calc["id"], "only", "kb-a", FAKE_LOADER=loader)
        assert not failed["ok"] and words in failed["error"], (loader, failed)
        assert store.read_text() == before, loader

    # A confirmed change carries its version like the other writes.
    stale = run("--expect", "0000000000000000", "scope", calc["id"], "only", "kb-a")
    assert not stale["ok"] and stale.get("stale"), stale
    version = run("bindings")["version"]
    assert run("--expect", version, "scope", calc["id"], "only", "kb-a")["ok"]

    # Deleting one keeps the other on its keyboards; the chord stays bound.
    assert run("delete", calc["id"])["ok"], "the chord is still Notes' on kb-b and kb-c"
    assert app("org.example.Notes")["chord"] == "SUPER + ALT + E"
    assert run("scope", notes["id"], "all")["ok"]
    stored = json.loads(store.read_text())["binds"]
    assert len(stored) == 1 and "devices" not in stored[0] and "device" not in compiled.read_text(), stored
print("PASS: scope limits app shortcuts to keyboards, shares chords only across disjoint keyboards and verifies Hyprland")
