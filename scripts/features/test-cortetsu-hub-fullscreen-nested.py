#!/usr/bin/env python3
"""The Hub under a fullscreen window, in a nested Hyprland with the real shell.

The installed Cortetsu runtime runs in a private nested Hyprland (own HOME,
XDG dirs, runtime dir and D-Bus session, Mesa only), so nothing reaches the
desktop. The Hub maps in Hyprland's top layer, which a fullscreen window covers (a
hidden nested compositor renders no frames, so this is read from Hyprland's
state, not from pixels); with a window fullscreen, SUPER+N's guard keeps the
notification center from opening over it.

    test-cortetsu-hub-fullscreen-nested.py [OUT]
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))
from nested_gpu import MESA_ONLY, compositor_env  # noqa: E402

RUNTIME = Path.home() / ".config/quickshell/cortetsu/current"
CONFIG = """hl.config({ animations = { enabled = false }, misc = { disable_hyprland_logo = true } })
"""


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(tempfile.mkdtemp(prefix="hubfs"))
    out.mkdir(parents=True, exist_ok=True)
    failures: list[str] = []

    def check(ok: bool, message: str) -> None:
        if not ok:
            failures.append(message)
            print("FAIL:", message, flush=True)

    with tempfile.TemporaryDirectory(prefix="czh", dir="/tmp") as tmp:
        base = Path(tmp)
        runtime = base / "r"
        runtime.mkdir(mode=0o700)
        (base / "cfg/hypr").mkdir(parents=True)
        (base / "cfg/hypr/hyprland.lua").write_text(CONFIG)
        parent = os.environ["WAYLAND_DISPLAY"]
        parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        env = {"HOME": str(base), "PATH": os.environ["PATH"], "LANG": "es_ES.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(base / "cfg"), "XDG_STATE_HOME": str(base / "state"),
               "XDG_CACHE_HOME": str(base / "cache"), "XDG_DATA_HOME": str(base / "data"),
               "QS_DISABLE_CRASH_HANDLER": "1"}
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        shell = client = None
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline and not (runtime / "hypr").is_dir():
                time.sleep(0.1)
            time.sleep(1)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = next((runtime / "hypr").iterdir()).name
            env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.iterdir() if p.name.startswith("wayland-") and not p.name.endswith(".lock"))
            env.update(MESA_ONLY)

            def hyprctl(*args: str) -> str:
                return subprocess.run(["hyprctl", *args], env=env, text=True, capture_output=True, timeout=10).stdout

            def layers() -> list[str]:
                found = []
                for data in json.loads(hyprctl("layers", "-j") or "{}").values():
                    for items in data.get("levels", {}).values():
                        found += [item.get("namespace", "") for item in items]
                return found

            def shot(name: str) -> Path:
                path = out / f"{name}.png"
                subprocess.run(["grim", str(path)], env=env, timeout=15, check=False)
                return path

            def band_luma(path: Path) -> float:
                # Mean luma of the bottom 70 px, where a bottom Hub sits.
                text = subprocess.run(["magick", str(path), "-gravity", "south", "-crop", "100%x70+0+0", "+repage",
                                       "-colorspace", "Gray", "-format", "%[fx:mean]", "info:"],
                                      text=True, capture_output=True).stdout
                return float(text or 0)

            log = (base / "qs.log").open("w")
            shell = subprocess.Popen(["dbus-run-session", "--", "qs", "-p", str(RUNTIME / "shell.qml"), "-n"],
                                     env=env, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline and "cortetsu-bottom-hub" not in layers():
                time.sleep(0.5)
            check("cortetsu-bottom-hub" in layers(), f"the Hub never mapped ({layers()})")
            time.sleep(2)

            # A plain white window, so the band under a fullscreen one is known.
            client = subprocess.Popen(["kitty", "--class", "hubfs", "-o", "background=#ffffff", "-o", "foreground=#ffffff",
                                       "-o", "hide_window_decorations=yes", "sh", "-c", "sleep 60"],
                                      env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            deadline = time.monotonic() + 15
            while time.monotonic() < deadline and "hubfs" not in hyprctl("clients"):
                time.sleep(0.3)
            time.sleep(1.5)
            levels = {}
            for data in json.loads(hyprctl("layers", "-j") or "{}").values():
                for level, items in data.get("levels", {}).items():
                    for item in items:
                        levels[item.get("namespace", "")] = level
            # Hyprland draws a fullscreen window over the top layer (2) and
            # under overlay (3): the Hub must live in top to be covered.
            check(levels.get("cortetsu-bottom-hub") == "2", f"the Hub is not in the top layer ({levels.get('cortetsu-bottom-hub')})")

            hyprctl("dispatch", 'hl.dsp.focus({ window = "class:hubfs" })')
            hyprctl("dispatch", 'hl.dsp.window.fullscreen({ mode = "fullscreen" })')
            time.sleep(1.5)
            state = json.loads(hyprctl("activewindow", "-j") or "{}")
            check(state.get("fullscreen", 0) == 2, f"the window did not go fullscreen ({state.get('fullscreen')})")

            # SUPER+N's guard: the notification center does not open over it.
            subprocess.run(["qs", "ipc", "-p", str(RUNTIME / "shell.qml"), "call", "drawers", "toggle", "sidebar"], env=env,
                           capture_output=True, timeout=10)
            time.sleep(1)
            opened = subprocess.run(["qs", "ipc", "-p", str(RUNTIME / "shell.qml"), "call", "drawers", "isOpen", "sidebar"],
                                    env=env, text=True, capture_output=True, timeout=10).stdout.strip().splitlines()[-1:] or [""]
            opened = opened[0].strip()
            check(opened == "0", f"the notification center opened over a fullscreen window ({opened})")
            print(f"Hub layer {levels.get('cortetsu-bottom-hub')}; fullscreen {state.get('fullscreen')}; sidebar over it: {opened}", flush=True)
        finally:
            for proc in (client, shell):
                if proc and proc.poll() is None:
                    os.killpg(proc.pid, 9)
            compositor.terminate()
            try:
                compositor.wait(timeout=10)
            except subprocess.TimeoutExpired:
                compositor.kill()
    if failures:
        print(f"FAIL: {len(failures)} Hub fullscreen checks")
        return 1
    print("PASS: with the real shell in a nested Hyprland the Hub sits in the top layer a fullscreen window covers, and the notification center does not open over that window")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
