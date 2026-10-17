#!/usr/bin/env python3
"""Shortcut capture holds Hyprland's binds and always lets them go.

A nested Hyprland loads the repository's real Lua config. A marker bind on
SUPER + F9 proves when global binds fire. `cortetsu-keybinds capture` must:
hold every bind while capturing, give them back on `end`, give them back by
itself when its timer runs out (the editor died), and never let the timer of
an older capture end a newer one.
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

KEY_LEFTMETA, KEY_F9 = 125, 67


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY") or not all(
            shutil.which(tool) for tool in ("Hyprland", "cc", "wayland-scanner", "pkg-config")):
        print("SKIP: requiere Wayland, Hyprland y un compilador para el teclado virtual")
        return 0
    helper = keybinds_helper.command()
    with tempfile.TemporaryDirectory(prefix="czc", dir="/tmp") as tmp:
        base = Path(tmp)
        hypr = base / "home/.config/hypr"
        hypr.parent.mkdir(parents=True)
        shutil.copytree(REPO / "dotfiles/home/.config/hypr", hypr, symlinks=True)
        shutil.copy(REPO / "config/hypr-user.lua", hypr / "hypr-user.lua")
        loader = hypr / "hyprland.lua"
        loader.write_text("-- Test loader: no startup programs.\nhl.exec_cmd = function() end\n" + loader.read_text())
        runtime = base / "run"
        runtime.mkdir(mode=0o700)
        fired = base / "fired"
        parent = os.environ["WAYLAND_DISPLAY"]
        parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        # XDG_CONFIG_HOME too: the session's own would point the helper at the real store.
        env = {"HOME": str(base / "home"), "XDG_CONFIG_HOME": str(base / "home/.config"), "PATH": os.environ["PATH"],
               "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime)}
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        keyboard = None
        try:
            socket = wait_for(lambda: sorted(p.name for p in runtime.glob("wayland-*[0-9]")), "Hyprland anidado")[0]
            signature = wait_for(lambda: next((p.name for p in (runtime / "hypr").iterdir()), None)
                                 if (runtime / "hypr").is_dir() else None, "instancia")
            henv = dict(os.environ, **env, HYPRLAND_INSTANCE_SIGNATURE=signature)

            def hyprctl(*args: str) -> str:
                return subprocess.run(["hyprctl", *args], env=henv, text=True, capture_output=True, timeout=10).stdout

            def capture(*args: str) -> dict:
                result = subprocess.run([*helper, "capture", *args], env=henv, text=True, capture_output=True, timeout=20)
                return json.loads(result.stdout)

            wait_for(lambda: "cortetsu-capture:exit" in hyprctl("binds", "-j"), "configuración cargada")
            assert hyprctl("eval", f'hl.bind("SUPER + F9", hl.dsp.exec_cmd("echo hit >> {fired}"))').strip() == "ok"
            keyboard = subprocess.Popen([str(build_vinput(base / "vinput"))], env=dict(env, WAYLAND_DISPLAY=socket),
                                        stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            assert keyboard.stdout.readline().strip() == "ready"

            def press() -> bool:
                fired.unlink(missing_ok=True)
                for code, down in ((KEY_LEFTMETA, 1), (KEY_F9, 1), (KEY_F9, 0), (KEY_LEFTMETA, 0)):
                    keyboard.stdin.write(f"key {code} {down}\n")
                    keyboard.stdin.flush()
                    assert keyboard.stdout.readline().strip() == "ok"
                    time.sleep(0.03)
                time.sleep(0.4)
                return fired.exists()

            wait_for(press, "el bind marcador responde")
            started = capture("begin", "15000")
            assert started["ok"] and started["active"] and started["submap"] == "cortetsu-capture", started
            assert not press(), "a global bind fired while capturing"
            ended = capture("end")
            assert ended["ok"] and not ended["active"], ended
            assert press(), "binds did not come back after end"

            # The editor died: its timer gives the keyboard back on its own.
            assert capture("begin", "1200")["active"]
            time.sleep(1.8)
            assert not capture("status")["active"], "the fail-safe timer did not leave the submap"
            assert press()

            # An older capture's timer cannot end a newer capture.
            assert capture("begin", "1000")["active"] and not capture("end")["active"]
            assert capture("begin", "6000")["active"]
            time.sleep(1.6)
            assert capture("status")["active"], "a stale timer ended the newer capture"
            assert not capture("end")["active"] and press()
            assert not capture("end")["active"], "ending twice is harmless"

            # A config reload during a capture never leaves the keyboard held:
            # either the reload leaves the submap or the fail-safe still runs.
            assert capture("begin", "1500")["active"]
            hyprctl("reload")
            wait_for(lambda: "cortetsu-capture:exit" in hyprctl("binds", "-j"), "configuración recargada")
            time.sleep(2.5)
            after_reload = capture("status")
            assert not after_reload["active"], f"a reload kept the submap without its fail-safe: {after_reload}"
        finally:
            for process in (keyboard, compositor):
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()
    print("PASS: la captura retiene los binds de Hyprland, los devuelve al terminar o al agotar su tiempo, "
          "un temporizador viejo no corta una captura nueva y recargar Hyprland no deja el teclado retenido")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
