#!/usr/bin/env python3
"""The HP Victus key binds in config/hypr-user.lua fire from the keys' codes.

A nested Hyprland with the latam layout loads the shipped bind strings, each
bound to a marker command, plus the launcher's Super release bind, and a
virtual keyboard sends the evdev codes the laptop produces (OMEN: KEY_PROG2
on HP WMI hotkeys; Copilot: Super+Shift+F23 on the AT keyboard). Copilot must
fire only its own bind, not the launcher; plain F23 and Shift+F23 must fire
nothing. This proves the keysym match; physical presses stay PENDING_PHYSICAL.
"""
from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent / "lib"))
import keybinds_helper  # noqa: E402
from launcher_harness import build_vinput, wait_for  # noqa: E402
from nested_gpu import compositor_env  # keeps a suspended dGPU asleep  # noqa: E402

KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_PROG2, KEY_F23 = 125, 42, 149, 193
# chord as shipped -> (global it must dispatch, marker the nested bind writes)
HP_BINDS = {"XF86Launch2": ("cortetsu:hardwareKey", "omen"),
            "SUPER + SHIFT + F23": ("cortetsu:osd", "copilot")}


def _rows(node) -> list[dict]:
    """Every bind row in the editor's JSON, whatever its grouping."""
    if isinstance(node, dict):
        return [node] if "chord" in node else [row for value in node.values() for row in _rows(value)]
    if isinstance(node, list):
        return [row for value in node for row in _rows(value)]
    return []


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY") or not all(
            shutil.which(tool) for tool in ("Hyprland", "cc", "wayland-scanner", "pkg-config")):
        print("SKIP: requiere Wayland, Hyprland y un compilador para el teclado virtual")
        return 0

    user = (REPO / "config/hypr-user.lua").read_text(encoding="utf-8")
    # The launcher's default chord, read from keybinds.lua so this test
    # follows it if it changes.
    keybinds = (REPO / "dotfiles/home/.config/hypr/hyprland/keybinds.lua").read_text(encoding="utf-8")
    launcher = re.search(r'launcher_default = normalise_keybind\("([^"]+)"\)', keybinds).group(1)
    shipped = set(re.findall(r'hl\.bind\(\s*"([^"]+)",\s*hl\.dsp\.global\("([^"]+)"\)', user))
    expected = {(chord, target) for chord, (target, _) in HP_BINDS.items()}
    assert expected <= shipped, f"missing HP binds: {expected - shipped}"

    with tempfile.TemporaryDirectory(prefix="cortetsu-hp-keys-") as tmp:
        base = Path(tmp)
        # The shortcut editor (Hardware > Teclas) lists both as editable and
        # deletable with no conflicts: that is each bind's way back.
        hypr = base / "home/.config/hypr"
        shutil.copytree(REPO / "dotfiles/home/.config/hypr", hypr, symlinks=True)
        shutil.copy(REPO / "config/hypr-user.lua", hypr / "hypr-user.lua")
        listed = json.loads(subprocess.run(
            [*keybinds_helper.command(), "list"], env=dict(os.environ, HOME=str(base / "home")),
            text=True, capture_output=True, check=True, timeout=30).stdout)
        rows = {row["chord"]: row for row in _rows(listed)}
        for chord, (target, _) in HP_BINDS.items():
            row = rows.get(chord)
            assert row and row["action"] == {"global": target}, f"editor does not list {chord}: {row}"
            assert row["editable"] and row["deletable"] and not row["conflicts"], row
        runtime = base / "run"
        runtime.mkdir(mode=0o700)
        (base / "cfg/hypr").mkdir(parents=True)
        fired = base / "fired"
        lines = ['hl.config({ input = { kb_layout = "latam" }, misc = { disable_hyprland_logo = true } })',
                 # keybinds.lua: the launcher opens on a bare Super release.
                 f'hl.bind("{launcher}", hl.dsp.exec_cmd("echo launcher >> {fired}"), {{ release = true }})']
        for chord, (_, marker) in HP_BINDS.items():
            lines.append(f'hl.bind("{chord}", hl.dsp.exec_cmd("echo {marker} >> {fired}"))')
        (base / "cfg/hypr/hyprland.lua").write_text("\n".join(lines) + "\n")
        vinput = build_vinput(base / "vinput")
        parent = os.environ["WAYLAND_DISPLAY"]
        parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        env = {"HOME": str(base), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(base / "cfg")}
        nested_env = dict(env, WAYLAND_DISPLAY=parent)
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(nested_env, base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        keyboard = None
        try:
            socket = wait_for(lambda: sorted(p.name for p in runtime.glob("wayland-*[0-9]")), "Hyprland anidado")[0]
            keyboard = subprocess.Popen([str(vinput)], env=dict(env, WAYLAND_DISPLAY=socket, VINPUT_LAYOUT="latam"),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert keyboard.stdout.readline().strip() == "ready", "virtual keyboard did not start"

            def send(code: int, down: int) -> None:
                keyboard.stdin.write(f"key {code} {down}\n")
                keyboard.stdin.flush()
                assert keyboard.stdout.readline().strip() == "ok"
                time.sleep(0.03)

            def chord(*codes: int) -> list[str]:
                fired.unlink(missing_ok=True)
                for code in codes:
                    send(code, 1)
                for code in reversed(codes):
                    send(code, 0)
                time.sleep(0.5)  # the negative checks need a quiet window
                return fired.read_text().split() if fired.exists() else []

            # A bare Super tap proves the keyboard reaches the binds before
            # anything is asserted about the HP keys.
            wait_for(lambda: chord(KEY_LEFTMETA) == ["launcher"], "bind de Super del lanzador")
            assert chord(KEY_PROG2) == ["omen"], "OMEN (KEY_PROG2 → XF86Launch2) must open the Hardware Center"
            assert chord(KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_F23) == ["copilot"], \
                "Copilot must fire its own bind and not the launcher's Super release"
            assert chord(KEY_F23) == [], "plain F23 belongs to applications"
            assert chord(KEY_LEFTSHIFT, KEY_F23) == [], "Shift+F23 belongs to applications"
        finally:
            for process in (keyboard, compositor):
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()

    print("PASS: OMEN and Copilot binds fire from their key codes under latam; "
          "Copilot leaves the launcher closed; F23 and Shift+F23 stay with applications")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
