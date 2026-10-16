#!/usr/bin/env python3
"""The HP Victus key binds in config/hypr-user.lua fire from the keys' codes.

A nested Hyprland with the latam layout loads the same bind strings, each
bound to a marker command, and a virtual keyboard sends the evdev codes the
laptop produces (OMEN: KEY_PROG2 on HP WMI hotkeys; Copilot: Super+Shift+F23
on the AT keyboard). Plain F23 and Shift+F23 must not fire the Copilot bind.
This proves the keysym match; the physical key presses stay PENDING_PHYSICAL.
"""
from __future__ import annotations

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
from launcher_harness import build_vinput  # noqa: E402
try:
    from nested_gpu import compositor_env  # keeps a suspended dGPU asleep
except ImportError:  # TODO(#34): drop once nested_gpu.py is on main
    def compositor_env(env: dict, base: Path) -> dict:
        return env

KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_PROG2, KEY_F23 = 125, 42, 149, 193
HP_BINDS = {"cortetsu:hardware": "omen", "cortetsu:osd": "copilot"}

if not os.environ.get("WAYLAND_DISPLAY") or not all(shutil.which(t) for t in ("Hyprland", "cc", "wayland-scanner")):
    print("SKIP: requiere Wayland, Hyprland y un compilador para el teclado virtual")
    raise SystemExit(0)

# The bind strings exactly as shipped, keyed by the global they dispatch.
user = (REPO / "config/hypr-user.lua").read_text(encoding="utf-8")
binds = {match.group(2): match.group(1) for match in
         re.finditer(r'hl\.bind\(\s*"([^"]+)",\s*hl\.dsp\.global\("([^"]+)"\)', user)}
assert set(HP_BINDS) <= set(binds), f"missing HP binds: {set(HP_BINDS) - set(binds)}"

with tempfile.TemporaryDirectory(prefix="cortetsu-hp-keys-") as tmp:
    base = Path(tmp)
    runtime = base / "run"
    runtime.mkdir(mode=0o700)
    (base / "cfg/hypr").mkdir(parents=True)
    lines = ['hl.config({ input = { kb_layout = "latam" }, misc = { disable_hyprland_logo = true } })']
    for name, marker in HP_BINDS.items():
        lines.append(f'hl.bind("{binds[name]}", hl.dsp.exec_cmd("echo {marker} >> {base}/fired"))')
    (base / "cfg/hypr/hyprland.lua").write_text("\n".join(lines) + "\n")
    vinput = build_vinput(base / "vinput")
    parent = os.environ["WAYLAND_DISPLAY"]
    parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
    env = {"HOME": str(base), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
           "XDG_CONFIG_HOME": str(base / "cfg")}
    compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    keyboard = None
    try:
        deadline = time.monotonic() + 20
        while not list(runtime.glob("wayland-*[0-9]")):
            assert time.monotonic() < deadline, "nested Hyprland did not start"
            time.sleep(0.1)
        socket = sorted(p.name for p in runtime.glob("wayland-*[0-9]"))[0]
        keyboard = subprocess.Popen([str(vinput)], env=dict(env, WAYLAND_DISPLAY=socket, VINPUT_LAYOUT="latam"),
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
        assert keyboard.stdout.readline().strip() == "ready", "virtual keyboard did not start"

        def send(code: int, down: int) -> None:
            keyboard.stdin.write(f"key {code} {down}\n")
            keyboard.stdin.flush()
            assert keyboard.stdout.readline().strip() == "ok"
            time.sleep(0.03)

        def chord(*codes: int) -> list[str]:
            fired = base / "fired"
            fired.unlink(missing_ok=True)
            for code in codes:
                send(code, 1)
            for code in reversed(codes):
                send(code, 0)
            time.sleep(0.5)
            return fired.read_text().split() if fired.exists() else []

        time.sleep(1)
        assert chord(KEY_PROG2) == ["omen"], "OMEN (KEY_PROG2 → XF86Launch2) must open the Hardware Center"
        assert chord(KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_F23) == ["copilot"], \
            f"Copilot (Super+Shift+F23) must match {binds['cortetsu:osd']!r}"
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

print("PASS: OMEN and Copilot binds fire from their key codes under latam; F23 and Shift+F23 stay with applications")
