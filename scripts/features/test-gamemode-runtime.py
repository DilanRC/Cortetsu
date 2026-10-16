#!/usr/bin/env python3
"""Game mode is reversible against a real nested Hyprland.

Compares every option's live value (`hyprctl getoption`, all names) before
enable and after disable, and covers: a repeated enable, an option changed by
Settings while game mode is on, a shell restart in the middle (recovery from
the snapshot), and a disable with nothing to restore.
"""
from __future__ import annotations

import json
import os
import runpy
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "cortetsu/bin/cortetsu-gamemode"
GAME = runpy.run_path(str(HELPER))["GAME"]
sys.path.insert(0, str(REPO / "scripts/integration"))
try:
    from nested_gpu import compositor_env  # keeps a suspended dGPU asleep
# TODO(#34): drop this fallback once nested_gpu.py is on main.
except ImportError:
    def compositor_env(env: dict, base: Path) -> dict:
        return env

CONFIG = """hl.config({
    general = { gaps_in = 5, gaps_out = "4 8 12 16", border_size = 2, allow_tearing = false },
    decoration = { rounding = 15, blur = { enabled = true }, shadow = { enabled = true } },
    animations = { enabled = true },
    misc = { disable_hyprland_logo = true },
})
"""

if not os.environ.get("WAYLAND_DISPLAY"):
    print("SKIP: requiere una sesión Wayland para anidar Hyprland")
    raise SystemExit(0)

with tempfile.TemporaryDirectory(prefix="cortetsu-gamemode-") as tmp:
    base = Path(tmp)
    runtime = base / "run"
    runtime.mkdir(mode=0o700)
    (base / "cfg/hypr").mkdir(parents=True)
    (base / "cfg/hypr/hyprland.lua").write_text(CONFIG)
    parent = os.environ["WAYLAND_DISPLAY"]
    parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
    env = {"HOME": str(base), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
           "XDG_CONFIG_HOME": str(base / "cfg")}
    compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline and not (runtime / "hypr").is_dir():
            time.sleep(0.1)
        time.sleep(0.5)
        instance = next((runtime / "hypr").iterdir()).name
        env["HYPRLAND_INSTANCE_SIGNATURE"] = instance

        def hyprctl(*args: str) -> str:
            return subprocess.run(["hyprctl", *args], env=env, text=True, capture_output=True, check=True, timeout=10).stdout

        # descriptions' "current" reports defaults in 0.56; getoption is live.
        names: list[str] = []

        def effective() -> dict:
            names[:] = names or [item["name"] for item in json.loads(hyprctl("descriptions", "-j"))]
            values = {}
            for name in names:
                raw = hyprctl("getoption", name, "-j")
                try:
                    data = json.loads(raw)
                except ValueError:
                    values[name] = raw  # a few option types print no JSON; the text still compares
                    continue
                data.pop("set", None)
                data.pop("option", None)
                values[name] = next(iter(data.values()), None)
            return values

        def gamemode(action: str) -> dict:
            out = subprocess.run(["python3", str(HELPER), action], env=env, text=True, capture_output=True,
                                 check=True, timeout=20).stdout
            return json.loads(out)

        def option(name: str):
            return effective()[name]

        deadline = time.monotonic() + 20
        while True:
            probe = subprocess.run(["hyprctl", "getoption", "general:border_size", "-j"], env=env, text=True,
                                   capture_output=True, timeout=10)
            if probe.returncode == 0 and json.loads(probe.stdout).get("int") == 2:
                break
            assert time.monotonic() < deadline, f"nested Hyprland IPC: {probe.stdout}{probe.stderr}"
            time.sleep(0.2)
        before = effective()
        assert before["general:gaps_out"] != before["general:gaps_in"], before["general:gaps_out"]
        assert before["general:border_size"] == 2 and before["decoration:rounding"] == 15, {k: before.get(k) for k in ("general:border_size", "decoration:rounding", "general:gaps_in")}
        assert gamemode("status") == {"enabled": False}
        assert gamemode("disable") == {"enabled": False}, "disable with nothing to restore is a no-op"
        assert effective() == before

        assert gamemode("enable") == {"enabled": True}
        on = effective()
        assert on["animations:enabled"] in (0, False) and on["decoration:blur:enabled"] in (0, False)
        assert on["decoration:rounding"] == 0 and on["general:border_size"] == 1
        assert on["general:allow_tearing"] in (1, True)
        changed = {name for name in before if before[name] != on[name]}
        assert changed <= set(GAME), f"game mode touched more than it owns: {sorted(changed)}"

        assert gamemode("enable") == {"enabled": True}, "a repeated enable keeps the first snapshot"
        assert gamemode("disable") == {"enabled": False}
        after = effective()
        assert after == before, {name: (before[name], after[name]) for name in before if before[name] != after.get(name)}

        # Settings changes rounding while game mode is on; disable keeps it.
        gamemode("enable")
        hyprctl("eval", "hl.config({ decoration = { rounding = 7 } })")
        gamemode("disable")
        after = effective()
        assert after["decoration:rounding"] == 7, "an option changed meanwhile is not overwritten"
        assert {n: v for n, v in after.items() if n != "decoration:rounding"} == \
            {n: v for n, v in before.items() if n != "decoration:rounding"}

        # The shell restarts in the middle: status recovers, disable restores.
        hyprctl("eval", "hl.config({ decoration = { rounding = 15 } })")
        gamemode("enable")
        assert gamemode("status") == {"enabled": True}, "a restarted shell sees game mode on"
        gamemode("disable")
        assert effective() == before
        assert not list(runtime.glob("cortetsu-gamemode-*.json")), "no snapshot left behind"

        # A quick on/off starts two helpers at once. Whatever order they run
        # in, the snapshot exists exactly when the game values are live.
        for _ in range(6):
            racers = [subprocess.Popen(["python3", str(HELPER), action], env=env, stdout=subprocess.PIPE, text=True)
                      for action in ("enable", "disable")]
            for racer in racers:
                racer.communicate(timeout=30)
            if gamemode("status")["enabled"]:
                assert option("decoration:rounding") == 0, "snapshot kept but game values missing"
                gamemode("disable")
            assert effective() == before, "an interleaved enable/disable lost the user's values"

        # QML wiring: a shell that starts while the snapshot exists shows game
        # mode on without applying it again; turning it off calls disable.
        shell = base / "shell"
        (shell / "modules").mkdir(parents=True)
        (shell / "services").mkdir()
        (shell / "services/GameMode.qml").write_text((REPO / "cortetsu/services/GameMode.qml").read_text())
        (shell / "modules/CortetsuConfig.qml").write_text(
            "pragma Singleton\nimport Quickshell\nSingleton { property bool toastGameModeChanged: false }\n")
        (shell / "modules/CortetsuHypr.qml").write_text(
            "pragma Singleton\nimport Quickshell\nSingleton { property bool usingLua: true }\n")
        (shell / "shell.qml").write_text(
            'import Quickshell\nimport Quickshell.Io\nimport "services"\nShellRoot {\n'
            '    IpcHandler { target: "harness"; function enabled(): bool { return GameMode.enabled } }\n}\n')
        fake = base / "fakebin"
        fake.mkdir()
        calls = base / "gamemode-calls"
        flag = base / "fake-on"
        flag.touch()
        (fake / "cortetsu-gamemode").write_text(f"""#!/bin/sh
echo "start $1" >> {calls}
sleep 0.3
case "$1" in
  enable) [ -f {base}/fail-enable ] || touch {flag} ;;
  disable) rm -f {flag} ;;
esac
echo "end $1" >> {calls}
[ -f {flag} ] && echo '{{"enabled": true}}' || echo '{{"enabled": false}}'
""")
        (fake / "cortetsu-gamemode").chmod(0o755)
        nested = dict(env, PATH=f"{fake}:{env['PATH']}", WAYLAND_DISPLAY=next(
            p.name for p in runtime.glob("wayland-*[0-9]")), QT_QPA_PLATFORM="wayland")
        log = (base / "qs.log").open("w")
        qs = subprocess.Popen(["qs", "-p", str(shell), "-n"], env=nested, stdout=log, stderr=subprocess.STDOUT,
                              start_new_session=True)
        try:
            def ipc(*args: str) -> str:
                return subprocess.run(["qs", "ipc", "--pid", str(qs.pid), "call", *args], env=nested, text=True,
                                      capture_output=True, timeout=10).stdout.strip()
            deadline = time.monotonic() + 20
            while ipc("harness", "enabled") != "true":
                assert qs.poll() is None, (base / "qs.log").read_text()
                assert time.monotonic() < deadline, "the shell did not recover game mode from status"
                time.sleep(0.2)
            def runs() -> list[str]:
                return [line.split()[1] for line in calls.read_text().splitlines() if line.startswith("start")]

            def settle(expected: list[str]) -> None:
                deadline = time.monotonic() + 15
                while runs() != expected or calls.read_text().count("start") != calls.read_text().count("end"):
                    assert time.monotonic() < deadline, calls.read_text()
                    time.sleep(0.1)

            assert runs() == ["status"], "recovery must not re-apply game mode"
            ipc("gameMode", "disable")
            settle(["status", "disable"])
            assert ipc("harness", "enabled") == "false"

            # A failed enable must not read as on.
            (base / "fail-enable").touch()
            ipc("gameMode", "enable")
            settle(["status", "disable", "enable"])
            deadline = time.monotonic() + 5
            while ipc("harness", "enabled") != "false":
                assert time.monotonic() < deadline, "a failed enable still shows game mode on"
                time.sleep(0.1)
            (base / "fail-enable").unlink()

            # Five quick toggles: helpers never overlap and the last request wins.
            for _ in range(5):
                ipc("gameMode", "toggle")
            deadline = time.monotonic() + 15
            while calls.read_text().count("start") != calls.read_text().count("end") or len(runs()) < 4:
                assert time.monotonic() < deadline, calls.read_text()
                time.sleep(0.1)
            time.sleep(1)
            lines = calls.read_text().splitlines()
            depth = 0
            for line in lines:
                depth += 1 if line.startswith("start") else -1
                assert depth <= 1, f"helpers overlapped: {lines}"
            assert ipc("harness", "enabled") == "true" and flag.exists(), "odd number of toggles from off ends on"
            log_text = (base / "qs.log").read_text()
            assert "WARN" not in log_text and "ERROR" not in log_text, log_text
        finally:
            os.killpg(qs.pid, 15)
            qs.wait(5)
            log.close()
    finally:
        compositor.terminate()
        try:
            compositor.wait(10)
        except subprocess.TimeoutExpired:
            compositor.kill()

print("PASS: game mode restores every effective Hyprland option, keeps changes made meanwhile and recovers after a shell restart")
