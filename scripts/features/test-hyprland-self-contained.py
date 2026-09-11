#!/usr/bin/env python3
"""
P0 regression: ~/.config/hypr must be a self-contained Lua module root.

Before this fix, hyprland.lua put ~/.config/caelestia on package.path, so
require("hyprland.keybinds") and friends silently resolved through the
Caelestia tree. Deleting ~/.config/caelestia/hyprland during the
Zero-Caelestia migration then dropped ~70 keybinds with no Lua error visible
in `hyprctl configerrors`.

This test proves the opposite: every required module and its transitive
dependencies load from dotfiles/home/.config/hypr alone, in a $HOME that has
no ~/.config/caelestia at all.
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HYPR_SRC = REPO / "dotfiles/home/.config/hypr"
SELF = Path(__file__).resolve().relative_to(REPO).as_posix()
LUA_BIN = shutil.which("lua5.4") or shutil.which("lua") or shutil.which("luajit")

REQUIRED_MODULES = [
    "hyprland.env", "hyprland.general", "hyprland.input", "hyprland.misc",
    "hyprland.animations", "hyprland.decoration", "hyprland.group",
    "hyprland.execs", "hyprland.rules", "hyprland.gestures", "hyprland.keybinds",
]
TRANSITIVE_FILES = ["variables.lua", "utils/functions.lua", "utils/json.lua", "scheme/default.lua"]
FORBIDDEN_DEPENDENCY = ".config/caelestia/hyprland"
# hypr-user.lua fully migrated to ~/.config/hypr/hypr-user.lua (dotfiles
# manifest target + every installer script). Nothing may read or write the
# old caelestia path again -- scripts/history/** and the identical frozen
# scripts/maintenance/caelestia-migrate-v2.1-official-tag.sh duplicate are
# exempt: both are records of already-executed one-off migrators, not
# active code (they targeted the v2.3.0 package upgrade and never run again).
FORBIDDEN_USER_OVERRIDE = ".config/caelestia/hypr-user.lua"

assert LUA_BIN, "no lua interpreter (lua5.4/lua/luajit) found on PATH"

# 1. Static gate: the package.path assignment itself must never mention
#    caelestia. (hyprland.lua's transitional hypr-user.lua dofile fallback,
#    further down the file, is allowed to mention it -- that's a plain
#    dofile() call, not a module-root change -- so this check is scoped to
#    just the assignment statement.)
loader_text = (HYPR_SRC / "hyprland.lua").read_text(encoding="utf-8")
path_assignment = re.search(r"^package\.path = .*$", loader_text, re.MULTILINE)
assert path_assignment, "hyprland.lua no longer sets package.path"
assert "caelestia" not in path_assignment.group(0).lower(), (
    "hyprland.lua package.path assignment references caelestia: " + path_assignment.group(0)
)

# 2. Static gate: no file in the repo may reference the deleted
#    ~/.config/caelestia/hyprland tree as an active dependency. This is the
#    gate the P0 fix explicitly requires so the regression can't come back.
hits = subprocess.run(
    ["git", "grep", "-n", "-I", "-F", FORBIDDEN_DEPENDENCY, "--", ".", f":!{SELF}", ":!docs/**"],
    cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
assert hits.returncode in (0, 1), f"git grep failed:\n{hits.stdout}"
assert hits.stdout.strip() == "", f"forbidden dependency on deleted Caelestia tree:\n{hits.stdout}"

# 2a. The direct window-to-workspace bindings must use the existing dynamic
#     workspace action. A static dispatcher with a numeric workspace is not
#     registered by Hyprland's Lua API and silently drops SUPER+SHIFT+#.
user_config = (REPO / "config/hypr-user.lua").read_text(encoding="utf-8")
assert 'local fn = require("utils.functions")' in user_config
assert 'local move_key = "SUPER + SHIFT + " .. key' in user_config
assert 'hl.bind(move_key, fn.wsaction("move", "", i))' in user_config
assert 'move_key = "SUPER + SHIFT + F7"' in user_config

# 2b. Same gate for the migrated hypr-user.lua: it now lives only at
# ~/.config/hypr/hypr-user.lua. Reintroducing the caelestia path as an active
# read/write target (loader, installer script, or manifest target) is exactly
# the P0 failure mode recurring in a different file.
user_hits = subprocess.run(
    ["git", "grep", "-n", "-I", "-F", FORBIDDEN_USER_OVERRIDE,
     "--", ".", f":!{SELF}", ":!docs/**", ":!scripts/history/**",
     ":!scripts/maintenance/caelestia-migrate-v2.1-official-tag.sh"],
    cwd=REPO, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
)
assert user_hits.returncode in (0, 1), f"git grep failed:\n{user_hits.stdout}"
assert user_hits.stdout.strip() == "", (
    f"forbidden reintroduction of legacy hypr-user.lua path:\n{user_hits.stdout}"
)

# 3. All required modules and their transitive dependencies exist as real,
#    Cortetsu-owned files (not resolved through some other tree).
for mod in REQUIRED_MODULES:
    rel = mod.replace(".", "/") + ".lua"
    assert (HYPR_SRC / rel).is_file(), f"missing required module: {rel}"
for rel in TRANSITIVE_FILES:
    assert (HYPR_SRC / rel).is_file(), f"missing transitive dependency: {rel}"

# 4. Dynamic proof: actually load the loader in a throwaway $HOME with NO
#    ~/.config/caelestia at all, using a permissive `hl` stub in place of
#    Hyprland's native dispatch API (dsp.*, bind, dispatch -- all no-ops that
#    never error). If any require() in the aggregated required_modules loop
#    fails, hyprland.lua's own error() surfaces here as a non-zero exit.
with tempfile.TemporaryDirectory(prefix="cortetsu-hypr-selfcontained-") as tmp:
    home = Path(tmp) / "home"
    hypr = home / ".config/hypr"
    shutil.copytree(HYPR_SRC, hypr)
    assert not (home / ".config/caelestia").exists(), "test setup leaked a caelestia dir"

    harness = Path(tmp) / "harness.lua"
    harness.write_text(
        "local function stub()\n"
        "    local t\n"
        "    t = setmetatable({}, {\n"
        "        __index = function() return stub() end,\n"
        "        __call = function() return stub() end,\n"
        "    })\n"
        "    return t\n"
        "end\n"
        "hl = stub()\n"
        "\n"
        "local target = ...\n"
        "dofile(target)\n"
        "print('CORTETSU_SELFCONTAINED_OK')\n"
        "print('PACKAGE_PATH=' .. package.path)\n",
        encoding="utf-8",
    )

    proc = subprocess.run(
        [LUA_BIN, str(harness), str(hypr / "hyprland.lua")],
        env={"HOME": str(home), "PATH": "/usr/bin:/bin"},
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    assert proc.returncode == 0, f"loader failed with no ~/.config/caelestia present:\n{proc.stdout}"
    assert "CORTETSU_SELFCONTAINED_OK" in proc.stdout, proc.stdout
    path_line = next(line for line in proc.stdout.splitlines() if line.startswith("PACKAGE_PATH="))
    assert "caelestia" not in path_line.lower(), f"caelestia leaked into package.path: {path_line}"
    assert str(hypr) in path_line, f"loader did not add the Cortetsu hypr tree to package.path: {path_line}"

print("PASS: ~/.config/hypr is a self-contained Lua module root; the deleted Caelestia hyprland tree is not required")
