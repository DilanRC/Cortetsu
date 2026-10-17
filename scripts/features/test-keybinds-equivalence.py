#!/usr/bin/env python3
"""The Rust cortetsu-keybinds behaves like the Python helper it replaced.

The Python helper is taken from Git (REFERENCE, the last commit that shipped
it). Both run the same operations in two identical homes, each with the fake
hyprctl of test-keybinds.py, on two configurations: the fixture of
test-keybinds.py and the repository's real Hyprland Lua. After every step
the answers, keybinds.json and the compiled cortetsu-keybinds.lua must
match; only the snapshot path, which names the home, is left out.

Known, intended differences are listed in DIFFERENCES and asserted as such.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(REPO / "scripts/lib"))
sys.path.insert(0, str(HERE))
import keybinds_helper  # noqa: E402

REFERENCE = "6e3fdaf"
SOURCE = (HERE / "test-keybinds.py").read_text(encoding="utf-8")
FAKE_HYPRCTL = SOURCE.split("FAKE_HYPRCTL = r'''", 1)[1].split("'''", 1)[0]
VARIABLES = SOURCE.split("VARIABLES = '''", 1)[1].split("'''", 1)[0]
USER = SOURCE.split("USER = '''", 1)[1].split("'''", 1)[0]
KEYBINDS = ('create_bind(vars.kbBrowser, hl.dsp.exec_cmd(vars.browser))\n'
            'create_bind(vars.kbNextWs, hl.dsp.focus({ workspace = "+1" }))\n'
            'create_bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), locked)\n'
            'create_bind({ "SUPER + SLASH", "SUPER + SHIFT + 7" }, hl.dsp.global("cortetsu:osd"))\n')


def python_reference(folder: Path) -> list[str]:
    try:
        text = subprocess.run(["git", "-C", str(REPO), "show", f"{REFERENCE}:cortetsu/bin/cortetsu-keybinds"],
                              text=True, capture_output=True, check=True).stdout
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"FAIL: no se pudo leer el helper Python de {REFERENCE} ({error.stderr.strip()}); "
                         "hace falta el historial completo (fetch-depth: 0)")
    path = folder / "cortetsu-keybinds.py"
    path.write_text(text)
    return [sys.executable, str(path)]


def fixture_home(home: Path) -> None:
    hypr = home / ".config/hypr"
    generation = home / "generation"
    (generation / "hyprland").mkdir(parents=True)
    hypr.mkdir(parents=True)
    (generation / "variables.lua").write_text(VARIABLES)
    (generation / "hypr-user.lua").write_text(USER)
    (generation / "hyprland/keybinds.lua").write_text(KEYBINDS)
    for name in ("variables.lua", "hypr-user.lua", "hyprland"):
        (hypr / name).symlink_to(generation / name)


def real_home(home: Path) -> None:
    hypr = home / ".config/hypr"
    hypr.parent.mkdir(parents=True)
    shutil.copytree(REPO / "dotfiles/home/.config/hypr", hypr, symlinks=True)
    shutil.copy(REPO / "config/hypr-user.lua", hypr / "hypr-user.lua")


class Side:
    def __init__(self, root: Path, command: list[str], build) -> None:
        self.home = root
        self.command = command
        build(root)
        fake = root / "hyprctl"
        fake.write_text(FAKE_HYPRCTL)
        fake.chmod(0o755)

    def run(self, *args: str, **env: str) -> tuple[dict, int]:
        result = subprocess.run([*self.command, *args], text=True, capture_output=True, timeout=60,
                                env=dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / ".config"),
                                         CORTETSU_HYPRCTL=str(self.home / "hyprctl"), **env))
        try:
            answer = json.loads(result.stdout)
        except ValueError:
            raise AssertionError(f"{self.command[-1]} {args}: no JSON\n{result.stdout}\n{result.stderr}")
        answer.pop("snapshot", None)
        if "error" in answer:
            answer["error"] = answer["error"].replace(str(self.home), "$HOME")
        return answer, result.returncode

    def state(self) -> tuple:
        store = self.home / ".config/cortetsu/keybinds.json"
        compiled = self.home / ".config/hypr/cortetsu-keybinds.lua"
        return (json.loads(store.read_text()) if store.exists() and not store.is_symlink() else None,
                compiled.read_text() if compiled.exists() else None)


# (step, python answer, rust answer) -> reason. Empty: none known.
DIFFERENCES: dict[str, str] = {}


def compare(python: Side, rust: Side, label: str, *args: str, **env: str) -> dict:
    left, left_code = python.run(*args, **env)
    right, right_code = rust.run(*args, **env)
    if left != right or left_code != right_code:
        if label in DIFFERENCES and not left.get("ok") and not right.get("ok"):
            return right
        raise AssertionError(f"{label}: {args}\npython={left_code} {json.dumps(left, ensure_ascii=False)}\n"
                             f"rust  ={right_code} {json.dumps(right, ensure_ascii=False)}")
    assert python.state() == rust.state(), f"{label}: store or compiled Lua differ\n{python.state()}\n{rust.state()}"
    listing_left, _ = python.run("list")
    listing_right, _ = rust.run("list")
    assert listing_left == listing_right, f"{label}: list differs afterwards"
    return right


def by(listing: dict, **wanted) -> dict:
    return next(item for item in listing["bindings"] if all(item.get(k) == v for k, v in wanted.items()))


def scenario_fixture(python: Side, rust: Side) -> int:
    steps = 0
    listing = compare(python, rust, "list", "list")
    spotify = by(listing, appName="Spotify")
    music = by(listing, chord="SUPER + J")
    lua_bind = by(listing, chord="SUPER + G")
    fixed = by(listing, chord="XF86AudioMute")
    for chord in ("CTRL + End", "CTRL + Down", "F5", "SUPER + Ñ", "HYPER + A", "SUPER + O", "SUPER + G", "MOD5 + Q",
                  "ALTGR + A", "", "SUPER + SHIFT", "control + alt + t", "SUPER + F25", "SUPER + SLASH",
                  "XF86Calculator", "XF86Launch2", "SUPER + SHIFT + F23", "CTRL + ALT + T", "SUPER + KP_1", "F13"):
        compare(python, rust, f"set kbBrowser {chord!r}", "set", "var:kbBrowser:0", chord)
        steps += 1
    for args in (("set", "var:kbNextWs:1", "SUPER + CTRL + Right"), ("set", spotify["id"], "SUPER + ALT + O"),
                 ("reset", spotify["id"]), ("set", music["id"], "SUPER + ALT + J"), ("reset", music["id"]),
                 ("set", lua_bind["id"], "SUPER + ALT + G"), ("set", fixed["id"], "SUPER + ALT + M"),
                 ("delete", fixed["id"]), ("reset", fixed["id"]), ("set", "var:nope:0", "SUPER + ALT + N"),
                 ("delete", "var:kbNextWs:0"), ("delete", "var:kbNextWs:0"), ("reset", "var:kbNextWs:-"),
                 ("add-app", "org.example.App", "Example", "example --open %U", "SUPER + ALT + E"),
                 ("add-app", "org.example.Two", "Two", "two  %f %u 100%%", "SUPER + ALT + R"),
                 ("add-app", "", "Broken", "x", "SUPER + ALT + Z"),
                 ("add-app", "org.example.Taken", "Taken", "taken", "SUPER + ALT + E"),
                 ("delete", spotify["id"]), ("reset", spotify["id"])):
        compare(python, rust, " ".join(args[:2]), *args)
        steps += 1
    listing = rust.run("list")[0]
    app = by(listing, appId="org.example.App")
    compare(python, rust, "set app", "set", app["id"], "SUPER + ALT + Y")
    compare(python, rust, "delete app", "delete", app["id"])
    compare(python, rust, "failing reload", "set", "var:kbBrowser:0", "SUPER + ALT + B", FAKE_RELOAD_FAILS="1")
    steps += 3
    # A store written by hand: extra fields survive, non-strings are coerced.
    for side in (python, rust):
        (side.home / ".config/cortetsu/keybinds.json").write_text(json.dumps({
            "variables": {"kbBrowser": ["SUPER + ALT + W"], "other": ["x"]}, "unbind": ["SUPER + J", 7],
            "binds": [{"id": "app:hand", "chord": "SUPER + ALT + H", "exec": "hand", "name": "Hand", "extra": 1},
                      {"id": "broken"}]}))
    compare(python, rust, "hand-made store", "list")
    compare(python, rust, "edit over a hand-made store", "set", "app:hand", "SUPER + ALT + K")
    for side in (python, rust):
        (side.home / ".config/cortetsu/keybinds.json").write_text("{ not json")
    left, _ = python.run("list")
    right, _ = rust.run("list")
    assert not left["ok"] and not right["ok"] and "no es JSON válido" in left["error"] and "no es JSON válido" in right["error"]
    for side in (python, rust):
        store = side.home / ".config/cortetsu/keybinds.json"
        store.unlink()
        (side.home / "elsewhere.json").write_text("{}")
        store.symlink_to(side.home / "elsewhere.json")
    compare(python, rust, "symlinked store", "set", "var:kbBrowser:0", "SUPER + ALT + B")
    assert all((side.home / "elsewhere.json").read_text() == "{}" for side in (python, rust))
    return steps + 4


def scenario_real(python: Side, rust: Side) -> int:
    listing = compare(python, rust, "real list", "list")
    assert len(listing["bindings"]) > 50, len(listing["bindings"])
    editable = [item for item in listing["bindings"] if item["editable"]]
    steps = 1
    for item in editable[:12]:
        compare(python, rust, f"real set {item['id']}", "set", item["id"], "SUPER + ALT + F9")
        compare(python, rust, f"real reset {item['id']}", "reset", item["id"])
        compare(python, rust, f"real reset again {item['id']}", "reset", item["id"])
        steps += 3
    witcher = next((item for item in listing["bindings"] if item.get("appName", "").startswith("The Witcher")), None)
    if witcher:
        compare(python, rust, "real witcher", "set", witcher["id"], "SUPER + CTRL + W")
        compare(python, rust, "real witcher reset", "reset", witcher["id"])
        steps += 2
    return steps


def main() -> int:
    rust_command = keybinds_helper.command()
    total = 0
    with tempfile.TemporaryDirectory(prefix="cortetsu-keybinds-equivalence-") as temporary:
        root = Path(temporary)
        python_command = python_reference(root)
        for name, build, scenario in (("fixture", fixture_home, scenario_fixture),
                                      ("real", real_home, scenario_real)):
            python = Side(root / f"{name}-python", python_command, build)
            rust = Side(root / f"{name}-rust", rust_command, build)
            total += scenario(python, rust)
    print(f"PASS: el helper Rust responde igual que el Python de {REFERENCE} en {total} operaciones, "
          "con el mismo keybinds.json y el mismo Lua compilado")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
