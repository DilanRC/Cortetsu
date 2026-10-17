#!/usr/bin/env python3
"""The key test makes a key VERIFIED only when it is pressed on its keyboard.

A nested Hyprland loads the repository's real Lua config. A fake sysfs
declares one keyboard whose node has the Hyprland name of a virtual keyboard;
a second virtual keyboard with another name presses the same keys.
`cortetsu-keybinds probe` must bind the spare keys on that keyboard alone,
record only real presses, remember them for the model on `end`, show them as
VERIFIED in `keys`, and leave no bind behind: after `end`, on its timer and
after a reload.
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

KEY_CALC = 140
TYPING = [1, 2, 3, 14, 15, 16, 17, 28, 29, 30, 42, 56, 57, 59, 87, 88, 97, 100, 103, 125]
SPARE = [140, 148, 149, 150, 155, 183, 184]


def encode(codes: list[int]) -> str:
    words = [0] * (max(codes) // 64 + 1)
    for code in codes:
        words[code // 64] |= 1 << (code % 64)
    return " ".join(f"{w:x}" for w in reversed(words))


def fake_sysfs(root: Path, name: str) -> None:
    """One keyboard node, laid out like /sys/class/input."""
    node = root / "devices/virtual/input/input0"
    (node / "event0").mkdir(parents=True)
    (node / "id").mkdir()
    (node / "capabilities").mkdir()
    for path, text in (("name", name), ("phys", ""), ("uniq", ""), ("id/bustype", "0006"), ("id/vendor", "0000"),
                       ("id/product", "0000"), ("capabilities/ev", "120013"),
                       ("capabilities/key", encode(TYPING + SPARE)), ("event0/dev", "13:64")):
        (node / path).write_text(text + "\n")
    (root / "class/input").mkdir(parents=True)
    (root / "class/input/event0").symlink_to(node / "event0")


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY") or not all(
            shutil.which(tool) for tool in ("Hyprland", "cc", "wayland-scanner", "pkg-config")):
        print("SKIP: requiere Wayland, Hyprland y un compilador para el teclado virtual")
        return 0
    helper = keybinds_helper.command()
    with tempfile.TemporaryDirectory(prefix="czp", dir="/tmp") as tmp:
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

            sysfs = base / "sys"
            fake_sysfs(sysfs, "hl-virtual-keyboard-vinput")
            penv = dict(henv, CORTETSU_SYSFS=str(sysfs), CORTETSU_UDEV_DATA=str(base / "udev"))

            def helper_run(*args: str) -> dict:
                result = subprocess.run([*helper, *args], env=penv, text=True, capture_output=True, timeout=40)
                return json.loads(result.stdout)

            wait_for(lambda: "cortetsu-capture:exit" in hyprctl("binds", "-j"), "configuración cargada")
            binary = build_vinput(base / "vinput")
            other = binary.with_name("vother")
            shutil.copy(binary, other)
            for program in (binary, other):
                keyboards.append(subprocess.Popen([str(program)], env=dict(env, WAYLAND_DISPLAY=socket),
                                                  stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True))
                assert keyboards[-1].stdout.readline().strip() == "ready"
            wait_for(lambda: len([k for k in json.loads(hyprctl("devices", "-j"))["keyboards"]
                                  if "virtual-keyboard" in k["name"]]) == 2 or None, "dos teclados virtuales")

            def press(keyboard: subprocess.Popen, code: int) -> None:
                for down in (1, 0):
                    keyboard.stdin.write(f"key {code} {down}\n")
                    keyboard.stdin.flush()
                    assert keyboard.stdout.readline().strip() == "ok"
                    time.sleep(0.03)
                time.sleep(0.3)

            inventory = helper_run("inventory")
            [device] = inventory["keyboards"]
            assert device["hyprlandLinked"], device
            started = helper_run("probe", "begin", device["id"], "20000")
            assert started["ok"] and started["active"] and KEY_CALC in started["codes"], started
            assert set(started["codes"]) <= set(SPARE), "only spare keys are tested"
            assert any(b["description"] == f"cortetsu-probe:{KEY_CALC}" for b in json.loads(hyprctl("binds", "-j")))
            press(keyboards[1], KEY_CALC)
            assert helper_run("probe", "status")["hits"] == [], "another keyboard's press counted"
            press(keyboards[0], KEY_CALC)
            status = helper_run("probe", "status")
            assert status["active"] and status["hits"] == [KEY_CALC], status
            ended = helper_run("probe", "end", device["id"])
            assert ended["ok"] and not ended["active"] and ended["verified"] == [KEY_CALC], ended
            assert not any(b["description"].startswith("cortetsu-probe:") for b in json.loads(hyprctl("binds", "-j")))
            press(keyboards[0], 148)
            after = helper_run("probe", "status")
            assert not after["active"] and after["hits"] == [], "a bind outlived the test"

            stored = json.loads((base / "home/.config/cortetsu/keyboards.json").read_text())
            assert stored["verified"] == {device["model"]: [KEY_CALC]}, stored
            keys = {k["code"]: k for k in helper_run("keys")["devices"][0]["keys"]}
            assert "VERIFIED" in keys[KEY_CALC]["states"] and keys[KEY_CALC]["confidence"] == "verified"
            assert "VERIFIED" not in keys[148]["states"], "an unpressed key stays unverified"
            assert keys[KEY_CALC]["suggestion"]["category"] == "Calculator", keys[KEY_CALC]

            # The editor died: the timer removes the binds and keeps the
            # presses for `end`; a reload removes them too.
            assert helper_run("probe", "begin", device["id"], "1200")["active"]
            press(keyboards[0], 148)
            time.sleep(1.8)
            assert not helper_run("probe", "status")["active"], "the timer did not end the test"
            late = helper_run("probe", "end", device["id"])
            assert late["hits"] == [148] and late["verified"] == [KEY_CALC, 148], late
            assert helper_run("probe", "end", device["id"])["hits"] == [], "a test is read once"
            assert helper_run("probe", "begin", device["id"], "20000")["active"]
            hyprctl("reload")
            wait_for(lambda: "cortetsu-capture:exit" in hyprctl("binds", "-j"), "configuración recargada")
            assert not helper_run("probe", "status")["active"], "a reload kept the test"
            assert not any(b["description"].startswith("cortetsu-probe:") for b in json.loads(hyprctl("binds", "-j")))
        finally:
            for process in (*keyboards, compositor):
                if process and process.poll() is None:
                    process.terminate()
                    try:
                        process.wait(10)
                    except subprocess.TimeoutExpired:
                        process.kill()
    print("PASS: la prueba de teclas solo cuenta pulsaciones del teclado probado, recuerda lo pulsado como VERIFIED "
          "y no deja binds al terminar, al agotar su tiempo ni al recargar Hyprland")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
