#!/usr/bin/env python3
"""The keybind editor against the real Lua config in a nested Hyprland.

The repo's dotfiles are laid out like a promoted generation: ~/.config/hypr
holds symlinks into a generation directory and a regular loader file. Startup
programs are not run (hl.exec_cmd is a no-op in the loader). The test edits,
reloads, restarts Hyprland, promotes and rolls back a generation, and checks
`hyprctl binds -j` each time; generation files must never change.
"""
from __future__ import annotations

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))
from nested_gpu import MESA_ONLY, compositor_env  # noqa: E402
import keybinds_helper  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
HELPER = keybinds_helper.command()


def tree_hash(root: Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_file() and not path.is_symlink() and "scheme" not in path.parts:
            digest.update(str(path.relative_to(root)).encode() + path.read_bytes())
    return digest.hexdigest()


def make_generation(base: Path, name: str) -> Path:
    generation = base / "generations" / name / "home/.config/hypr"
    shutil.copytree(REPO / "dotfiles/home/.config/hypr", generation, symlinks=True)
    shutil.copy(REPO / "config/hypr-user.lua", generation / "hypr-user.lua")
    return generation


def point_at(hypr: Path, generation: Path) -> None:
    """What promotion does: every managed entry is a symlink into the generation."""
    for entry in generation.iterdir():
        link = hypr / entry.name
        if entry.name == "hyprland.lua":
            continue
        if link.is_symlink() or link.exists():
            link.unlink() if link.is_symlink() or link.is_file() else shutil.rmtree(link)
        link.symlink_to(entry, target_is_directory=entry.is_dir())
    (hypr / "hyprland.lua").write_text(
        "-- Test loader: no startup programs.\n"
        "hl.exec_cmd = function() end\n"
        f'dofile("{generation}/hyprland.lua")\n')


class Nested:
    def __init__(self, base: Path, parent_socket: str):
        self.base = base
        self.runtime = base / "r"
        self.parent = parent_socket
        self.process = None

    def start(self) -> None:
        shutil.rmtree(self.runtime, ignore_errors=True)
        self.runtime.mkdir(mode=0o700)
        env = {"HOME": str(self.base / "home"), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(self.runtime),
               "WAYLAND_DISPLAY": self.parent}
        self.process = subprocess.Popen(["Hyprland"], cwd=self.base, env=compositor_env(env, self.base),
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if (self.runtime / "hypr").is_dir() and any((self.runtime / "hypr").iterdir()) and self.binds():
                return
            time.sleep(0.2)
        raise AssertionError("nested Hyprland did not load the config")

    def stop(self) -> None:
        if self.process:
            self.process.terminate()
            try:
                self.process.wait(10)
            except subprocess.TimeoutExpired:
                self.process.kill()

    def env(self) -> dict:
        instance = next((self.runtime / "hypr").iterdir()).name
        return dict(os.environ, **MESA_ONLY, HOME=str(self.base / "home"), XDG_RUNTIME_DIR=str(self.runtime),
                    HYPRLAND_INSTANCE_SIGNATURE=instance, XDG_CONFIG_HOME=str(self.base / "home/.config"))

    def hyprctl(self, *args: str) -> str:
        return subprocess.run(["hyprctl", *args], text=True, capture_output=True, env=self.env(), timeout=10).stdout

    def binds(self) -> list[dict]:
        try:
            return json.loads(self.hyprctl("binds", "-j") or "[]")
        except (ValueError, StopIteration, OSError):
            return []

    def bound(self, mask: int, key: str) -> list[str]:
        return [bind["description"] for bind in self.binds() if bind["modmask"] == mask and bind["key"].upper() == key.upper()]

    def helper(self, *args: str, **extra: str) -> dict:
        result = subprocess.run([*HELPER, *args], text=True, capture_output=True,
                                env=dict(self.env(), **extra), timeout=60)
        return json.loads(result.stdout)


def main() -> int:
    parent = os.environ.get("WAYLAND_DISPLAY")
    if not parent or not shutil.which("Hyprland"):
        print("SKIP: requiere una sesión Wayland y Hyprland para anidar")
        return 0
    parent_socket = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
    with tempfile.TemporaryDirectory(prefix="czk", dir="/tmp") as tmp:
        base = Path(tmp)
        hypr = base / "home/.config/hypr"
        hypr.mkdir(parents=True)
        gen_a, gen_b = make_generation(base, "a"), make_generation(base, "b")
        point_at(hypr, gen_a)
        sealed = {gen_a: tree_hash(gen_a), gen_b: tree_hash(gen_b)}
        store = base / "home/.config/cortetsu/keybinds.json"
        nested = Nested(base, parent_socket)
        try:
            nested.start()
            baseline = len(nested.binds())
            assert not nested.hyprctl("configerrors").strip(), nested.hyprctl("configerrors")

            # The navigation chords belong to applications again; the launchers moved.
            assert nested.bound(4, "End") == [] and nested.bound(4, "Down") == [], "CTRL+End/Down still global"
            assert nested.bound(72, "W") and nested.bound(72, "G"), "app launchers lost"
            assert nested.bound(65, "L") == ["cortetsu:kbSleep"] and nested.bound(72, "K") == ["cortetsu:kbKeepAwake"]

            listing = nested.helper("list")
            assert listing["ok"]
            by_id = {item["id"]: item for item in listing["bindings"]}
            session = by_id["var:kbSession:0"]
            assert session["origin"] == "default" and session["editable"]
            assert not any(item["id"].startswith("var:kbGoToWs") for item in listing["bindings"]), "modifier prefixes are not shortcuts"
            witcher = next(item for item in listing["bindings"] if item.get("appName", "").startswith("The Witcher"))
            assert witcher["origin"] == "user" and witcher["chord"] == "SUPER + ALT + W"

            # Refusals: typing chords, AltGr, and a chord already taken.
            for chord, words in (("CTRL + End", "aplicaciones"), ("Q", "tecla sola"), ("MOD5 + Q", "AltGr"),
                                 ("SUPER + ALT + W", "ya es")):
                refused = nested.helper("set", "var:kbSession:0", chord)
                assert not refused["ok"] and words in refused["error"], (chord, refused)
            assert not store.exists(), "a refused edit wrote the store"

            # Rebind a default: the new chord carries its action, the old one is free.
            mask_default = nested.bound(12, "Delete")
            assert mask_default == ["cortetsu:kbSession"], mask_default
            done = nested.helper("set", "var:kbSession:0", "SUPER + ALT + Y")
            assert done["ok"], done
            assert nested.bound(72, "Y") == ["cortetsu:kbSession"] and nested.bound(12, "Delete") == []
            assert (hypr / "cortetsu-keybinds.lua").is_file() and not (hypr / "cortetsu-keybinds.lua").is_symlink()

            # Survives a Hyprland restart, a promotion and a rollback.
            nested.stop()
            nested.start()
            assert nested.bound(72, "Y") == ["cortetsu:kbSession"], "lost after restart"
            point_at(hypr, gen_b)
            nested.hyprctl("reload")
            assert nested.bound(72, "Y") == ["cortetsu:kbSession"], "lost after promotion"
            point_at(hypr, gen_a)
            nested.hyprctl("reload")
            assert nested.bound(72, "Y") == ["cortetsu:kbSession"], "lost after rollback"

            # Delete leaves nothing behind; reset brings the default back.
            assert nested.helper("delete", "var:kbSession:0")["ok"]
            assert nested.bound(72, "Y") == [] and nested.bound(12, "Delete") == []
            assert any(item["id"] == "var:kbSession:-" for item in nested.helper("list")["bindings"])
            assert nested.helper("reset", "var:kbSession:-")["ok"]
            assert nested.bound(12, "Delete") == ["cortetsu:kbSession"]

            # A hypr-user.lua launcher moves through the edit layer, not by rewriting the file.
            moved = nested.helper("set", witcher["id"], "SUPER + CTRL + W")
            assert moved["ok"], moved
            assert nested.bound(72, "W") == [] and nested.bound(68, "W")[0].startswith("cortetsu-keybinds:edit:")
            original = next(item for item in nested.helper("list")["bindings"] if item["id"] == witcher["id"])
            assert not original["active"] and original["resettable"]
            assert nested.helper("reset", witcher["id"])["ok"]
            assert nested.bound(72, "W") == [""] and nested.bound(68, "W") == [], nested.bound(68, "W")

            # Applications: add, then remove without leftovers.
            added = nested.helper("add-app", "org.example.Test", "Test", "true --flag %U", "SUPER + ALT + Q")
            assert added["ok"], added
            app = next(item for item in nested.helper("list")["bindings"] if item.get("appId") == "org.example.Test")
            assert nested.bound(72, "Q") == ["cortetsu-keybinds:" + app["id"]]
            assert nested.helper("delete", app["id"])["ok"] and nested.bound(72, "Q") == []

            # A reload that fails rolls the files back.
            before = store.read_text()
            failing = base / "failing-hyprctl"
            failing.write_text('#!/bin/sh\n[ "$1" = reload ] && exit 1\nexec hyprctl "$@"\n')
            failing.chmod(0o755)
            refused = nested.helper("set", "var:kbSession:0", "SUPER + ALT + Y", CORTETSU_HYPRCTL=str(failing))
            assert not refused["ok"] and store.read_text() == before, refused

            # A corrupt edit file is ignored: the session keeps every default bind.
            (hypr / "cortetsu-keybinds.lua").write_text("return {")
            nested.hyprctl("reload")
            time.sleep(0.5)
            assert len(nested.binds()) >= baseline - 2 and nested.bound(12, "Delete") == ["cortetsu:kbSession"]

            # A hand-made edit file that turns a modifier prefix into a list,
            # or puts a number in a list, is ignored for those entries.
            (hypr / "cortetsu-keybinds.lua").write_text(
                'return { variables = { kbGoToWs = { "SUPER", "ALT" }, kbLock = { 5 } } }\n')
            nested.hyprctl("reload")
            time.sleep(0.5)
            assert nested.bound(64, "1") and nested.bound(64, "L") == ["cortetsu:kbLock"], "hand edit broke binds"

            # The store is never written through a symlink.
            elsewhere = base / "elsewhere.json"
            elsewhere.write_text("{}")
            store.unlink()
            store.symlink_to(elsewhere)
            refused = nested.helper("set", "var:kbSession:0", "SUPER + ALT + Y")
            assert not refused["ok"] and "enlace" in refused["error"] and elsewhere.read_text() == "{}", refused

            for generation, digest in sealed.items():
                assert tree_hash(generation) == digest, f"{generation} was modified"
        finally:
            nested.stop()
    print("PASS: el editor reasigna, borra y restablece en la configuración efectiva, sobrevive a reinicio, "
          "promoción y rollback, rechaza combinaciones de aplicaciones y nunca escribe generaciones ni symlinks")
    return 0


if __name__ == "__main__":
    sys.exit(main())
