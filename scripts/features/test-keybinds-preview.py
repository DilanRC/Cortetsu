#!/usr/bin/env python3
"""bindings, preview and --expect: the review step of «Atajos y teclados».

preview never writes; a confirmed change carries the version its preview
showed and is refused, with nothing written, if the configuration changed in
between. Same fixture and fake hyprctl as test-keybinds.py.
"""
from __future__ import annotations

import fcntl
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
FAKE_HYPRCTL = SOURCE.split("FAKE_HYPRCTL = r'''", 1)[1].split("'''", 1)[0]
VARIABLES = SOURCE.split("VARIABLES = '''", 1)[1].split("'''", 1)[0]
USER = SOURCE.split("USER = '''", 1)[1].split("'''", 1)[0]
HELPER = keybinds_helper.command()

with tempfile.TemporaryDirectory(prefix="cortetsu-keybinds-preview-") as temporary:
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

    def run(*args: str) -> tuple[dict, int]:
        result = subprocess.run([*HELPER, *args], text=True, capture_output=True, timeout=30,
                                env=dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                                         CORTETSU_HYPRCTL=str(fake)))
        return json.loads(result.stdout), result.returncode

    listing, code = run("bindings")
    assert code == 0 and listing["protocol"] == 2 and listing["kind"] == "bindings", listing
    version = listing["version"]
    assert len(version) == 16 and any(b["id"] == "var:kbBrowser:0" for b in listing["bindings"])

    preview, _ = run("preview", "set", "var:kbBrowser:0", "super + alt + b")
    assert preview["valid"] and not preview["conflict"] and preview["before"] == "SUPER + W", preview
    assert preview["after"] == "SUPER + ALT + b" and preview["version"] == version, preview
    assert not store.exists(), "preview wrote the store"

    taken, _ = run("preview", "set", "var:kbBrowser:0", "SUPER + O")
    assert not taken["valid"] and taken["conflict"] and "ya es «Spotify»" in taken["problem"], taken
    invalid, _ = run("preview", "set", "var:kbBrowser:0", "CTRL + End")
    assert not invalid["valid"] and not invalid["conflict"] and "aplicaciones" in invalid["problem"], invalid
    locked, _ = run("preview", "set", next(b["id"] for b in listing["bindings"] if b["chord"] == "SUPER + G"),
                    "SUPER + ALT + G")
    assert not locked["valid"] and not locked["conflict"] and "hypr-user.lua" in locked["problem"], locked
    app, _ = run("preview", "add-app", "SUPER + ALT + E")
    assert app["valid"] and app["before"] == "" and app["id"] == "", app
    missing, code = run("preview", "set", "var:nope:0", "SUPER + ALT + N")
    assert code == 1 and missing["error"]["code"] == "unknown-binding", missing

    # Confirm with the version the preview showed: applied and verified.
    done, code = run("--expect", version, "set", "var:kbBrowser:0", "SUPER + ALT + B")
    assert code == 0 and done["ok"], done
    new_version = run("bindings")[0]["version"]
    assert new_version != version

    # A second confirmation of the old preview is stale and writes nothing.
    before = store.read_text()
    stale, code = run("--expect", version, "set", "var:kbBrowser:0", "SUPER + ALT + V")
    assert code == 1 and not stale["ok"] and stale["stale"] and "cambió" in stale["error"], stale
    assert store.read_text() == before

    # A hand edit of hypr-user.lua also makes the version stale.
    (hypr / "hypr-user.lua").write_text(USER + '\nhl.bind("SUPER + ALT + X", hl.dsp.exec_cmd("x"))\n')
    stale, _ = run("--expect", new_version, "delete", "var:kbBrowser:0")
    assert stale.get("stale"), stale
    # Writes wait for the editor lock: the version check and the write
    # cannot interleave with another helper.
    store.with_suffix(".lock").touch()
    with open(store.with_suffix(".lock"), "w") as held:
        fcntl.flock(held, fcntl.LOCK_EX)
        waiting = subprocess.Popen([*HELPER, "delete", "var:kbBrowser:0"], stdout=subprocess.PIPE, text=True,
                                   env=dict(os.environ, HOME=str(home), XDG_CONFIG_HOME=str(home / ".config"),
                                            CORTETSU_HYPRCTL=str(fake)))
        try:
            waiting.wait(timeout=1)
            raise AssertionError("a write ran while another helper held the lock")
        except subprocess.TimeoutExpired:
            pass
    assert waiting.wait(timeout=30) == 0 and json.loads(waiting.stdout.read())["ok"]

    usage, code = run("--expect", new_version, "list")
    assert code == 2 and not usage["ok"], usage

print("PASS: preview no escribe y separa conflicto de combinación no válida; --expect rechaza una vista "
      "previa obsoleta sin escribir nada; las escrituras esperan al bloqueo")
