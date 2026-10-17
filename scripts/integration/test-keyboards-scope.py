#!/usr/bin/env python3
"""A shortcut limited to one keyboard fires on that keyboard alone.

A nested Hyprland loads the repository's real Lua config and two virtual
keyboards. `cortetsu-keybinds` adds two application shortcuts, limits each to
one keyboard and puts both on the same chord: each keyboard runs its own, the
real hyprland.lua reports the scopes the helper verifies, and going back to
every keyboard is refused while the other one still holds the chord.
"""
from __future__ import annotations

import json
import os
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
from launcher_harness import build_vinput, wait_for  # noqa: E402
from nested_gpu import compositor_env  # noqa: E402
import keybinds_helper  # noqa: E402

KEY_LEFTMETA, KEY_LEFTALT, KEY_F10 = 125, 56, 68


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY") or not all(
            shutil.which(tool) for tool in ("Hyprland", "cc", "wayland-scanner", "pkg-config")):
        print("SKIP: requiere Wayland, Hyprland y un compilador para el teclado virtual")
        return 0
    helper = keybinds_helper.command()
    with tempfile.TemporaryDirectory(prefix="czs", dir="/tmp") as tmp:
        base = Path(tmp)
        hypr = base / "home/.config/hypr"
        hypr.parent.mkdir(parents=True)
        shutil.copytree(REPO / "dotfiles/home/.config/hypr", hypr, symlinks=True)
        shutil.copy(REPO / "config/hypr-user.lua", hypr / "hypr-user.lua")
        loader = hypr / "hyprland.lua"
        loader.write_text("-- Test loader: no startup programs.\nhl.exec_cmd = function() end\n" + loader.read_text())
        runtime = base / "run"
        runtime.mkdir(mode=0o700)
        parent = os.environ["WAYLAND_DISPLAY"]
        parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        # XDG_CONFIG_HOME too: the session's own would point the helper at the real store.
        env = {"HOME": str(base / "home"), "XDG_CONFIG_HOME": str(base / "home/.config"), "PATH": os.environ["PATH"],
               "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime)}
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        keyboards = []
        try:
            socket = wait_for(lambda: sorted(p.name for p in runtime.glob("wayland-*[0-9]")), "Hyprland anidado")[0]
            signature = wait_for(lambda: next((p.name for p in (runtime / "hypr").iterdir()), None)
                                 if (runtime / "hypr").is_dir() else None, "instancia")
            henv = dict(os.environ, **env, HYPRLAND_INSTANCE_SIGNATURE=signature)

            def hyprctl(*args: str) -> str:
                return subprocess.run(["hyprctl", *args], env=henv, text=True, capture_output=True, timeout=10).stdout

            def helper_run(*args: str) -> dict:
                result = subprocess.run([*helper, *args], env=henv, text=True, capture_output=True, timeout=40)
                return json.loads(result.stdout)

            wait_for(lambda: "cortetsu-capture:exit" in hyprctl("binds", "-j"), "configuración cargada")
            # Two names: identical keyboards (x, x-1) are refused as targets.
            binary = build_vinput(base / "vinput")
            other = binary.with_name("vother")
            shutil.copy(binary, other)
            for program in (binary, other):
                keyboards.append(subprocess.Popen([str(program)],
                                                  env=dict(env, WAYLAND_DISPLAY=socket),
                                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True))
                assert keyboards[-1].stdout.readline().strip() == "ready"
            names = wait_for(lambda: (lambda n: n if len(n) == 2 else None)(
                [k["name"] for k in json.loads(hyprctl("devices", "-j"))["keyboards"] if "virtual-keyboard" in k["name"]]),
                "dos teclados virtuales")
            marks = {name: base / f"fired-{index}" for index, name in enumerate(names)}

            def press(keyboard: subprocess.Popen) -> set[str]:
                for mark in marks.values():
                    mark.unlink(missing_ok=True)
                for code, down in ((KEY_LEFTMETA, 1), (KEY_LEFTALT, 1), (KEY_F10, 1), (KEY_F10, 0),
                                   (KEY_LEFTALT, 0), (KEY_LEFTMETA, 0)):
                    keyboard.stdin.write(f"key {code} {down}\n")
                    keyboard.stdin.flush()
                    assert keyboard.stdout.readline().strip() == "ok"
                    time.sleep(0.03)
                time.sleep(0.5)
                return {name for name, mark in marks.items() if mark.exists()}

            ids = []
            for index, (name, mark) in enumerate(marks.items()):
                chord = "SUPER + ALT + F10" if index == 0 else "SUPER + ALT + F11"
                added = helper_run("add-app", f"org.example.K{index}", f"K{index}", f"touch {mark}", chord)
                assert added["ok"], added
                row = next(b for b in helper_run("list")["bindings"] if b.get("appId") == f"org.example.K{index}")
                scoped = helper_run("scope", row["id"], "only", name)
                assert scoped["ok"], scoped
                ids.append(row["id"])
            moved = helper_run("set", ids[1], "SUPER + ALT + F10")
            assert moved["ok"], moved
            report = hyprctl("repl", 'local b = _G.cortetsu_binds[%s]; return tostring(b.device_inclusive) .. "|" '
                             '.. table.concat(b.devices, ",")' % json.dumps(ids[1]))
            assert report.strip() == f"true|{names[1]}", report

            for keyboard, name in zip(keyboards, names):
                fired = wait_for(lambda: press(keyboard) or None, f"el atajo de {name} responde")
                assert fired == {name}, f"{name} ran {fired}"

            widened = helper_run("scope", ids[0], "all")
            assert not widened["ok"] and "ya es «K1»" in widened["error"], widened
            assert press(keyboards[1]) == {names[1]}, "a refused change left Hyprland changed"
        finally:
            for process in (*keyboards, compositor):
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()
    print("PASS: un atajo limitado a un teclado solo responde en ese teclado; dos atajos comparten combinación "
          "en teclados distintos y Hyprland confirma a qué teclados responde cada uno")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
