#!/usr/bin/env python3
"""Game mode is reversible against a real nested Hyprland.

Compares every option's live value (`hyprctl getoption`, all names) before
enable and after disable, and covers: a repeated enable, an option changed by
Settings while game mode is on, a shell restart in the middle, real partial
applies and failed restores (a hyprctl wrapper makes Hyprland reject part of
the eval), concurrent helpers, and the QML contract: the toggle only shows
on after the helper confirms ACTIVE.
"""
from __future__ import annotations

import json
import os
import runpy
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HELPER = REPO / "cortetsu/bin/cortetsu-gamemode"
GAME = runpy.run_path(str(HELPER))["GAME"]
sys.path.insert(0, str(REPO / "scripts/integration"))
from nested_gpu import compositor_env  # keeps a suspended dGPU asleep  # noqa: E402

CONFIG = """hl.config({
    general = { gaps_in = 5, gaps_out = "4 8 12 16", border_size = 2, allow_tearing = false },
    decoration = { rounding = 15, blur = { enabled = true }, shadow = { enabled = true } },
    animations = { enabled = true },
    misc = { disable_hyprland_logo = true },
})
"""


def without_helper(path: str) -> str:
    """PATH minus every directory that holds a cortetsu-gamemode, so the
    shell can only ever run the harness's fake (an installed copy in
    ~/.local/bin would otherwise answer once the fake is parked)."""
    return os.pathsep.join(d for d in path.split(os.pathsep)
                           if d and not os.access(os.path.join(d, "cortetsu-gamemode"), os.X_OK))


with tempfile.TemporaryDirectory() as tmp:  # runs even when the nested part skips
    installed = Path(tmp, "installed")
    installed.mkdir()
    (installed / "cortetsu-gamemode").write_text("#!/bin/sh\n")
    (installed / "cortetsu-gamemode").chmod(0o755)
    clean = without_helper(f"{installed}{os.pathsep}/usr/bin")
    assert str(installed) not in clean.split(os.pathsep) and "/usr/bin" in clean.split(os.pathsep), clean
    assert shutil.which("cortetsu-gamemode", path=clean) is None, "an installed helper leaks through PATH"

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

        # Fault injection on the real compositor. partial: the game values are
        # evaluated, then a bad key makes Hyprland return an error. fail: the
        # eval never reaches Hyprland.
        fault = base / "fault"
        wrapper = base / "hyprctl-faulty"
        wrapper.write_text(f"""#!/bin/sh
mode=$(head -n1 {fault} 2>/dev/null)
if [ "$1" = eval ] && [ -n "$mode" ]; then
  sed -i 1d {fault}
  case "$mode" in
    fail) echo "error: injected" >&2; exit 7 ;;
    partial) hyprctl eval "$2" >/dev/null; exec hyprctl eval 'hl.config({{ cortetsu_injected = 1 }})' ;;
  esac
fi
exec hyprctl "$@"
""")
        wrapper.chmod(0o755)
        faulty = dict(env, CORTETSU_HYPRCTL=str(wrapper))

        def gamemode(action: str, ok: bool = True) -> dict:
            done = subprocess.run(["python3", str(HELPER), action], env=faulty, text=True, capture_output=True,
                                  timeout=20)
            reply = json.loads(done.stdout)
            assert (done.returncode == 0) == ok == reply["ok"], (action, done)
            assert reply["enabled"] == (reply["state"] == "ACTIVE"), reply
            return reply

        def inject(*modes: str) -> None:
            fault.write_text("".join(f"{mode}\n" for mode in modes))

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
        assert gamemode("status")["state"] == "INACTIVE"
        assert gamemode("disable")["state"] == "INACTIVE", "disable with nothing to restore is a no-op"
        assert effective() == before

        assert gamemode("enable")["state"] == "ACTIVE"
        on = effective()
        assert on["animations:enabled"] in (0, False) and on["decoration:blur:enabled"] in (0, False)
        assert on["decoration:rounding"] == 0 and on["general:border_size"] == 1
        assert on["general:allow_tearing"] in (1, True)
        changed = {name for name in before if before[name] != on[name]}
        assert changed <= set(GAME), f"game mode touched more than it owns: {sorted(changed)}"

        assert gamemode("enable")["state"] == "ACTIVE", "a repeated enable keeps the first snapshot"
        assert gamemode("disable")["state"] == "INACTIVE"
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
        assert gamemode("status")["state"] == "ACTIVE", "a restarted shell sees game mode on"
        gamemode("disable")
        assert effective() == before
        assert not list(runtime.glob("cortetsu-gamemode-*.json")), "no transaction left behind"

        # Hyprland rejects the eval outright: nothing moved, INACTIVE.
        inject("fail")
        reply = gamemode("enable", ok=False)
        assert reply["state"] == "INACTIVE" and "injected" in reply["error"], reply
        assert effective() == before

        # Hyprland applies the game values, then errors: rolled back for real.
        inject("partial")
        assert effective()["decoration:rounding"] == 15
        reply = gamemode("enable", ok=False)
        assert reply["state"] == "INACTIVE" and "rolled back" in reply["error"], reply
        assert effective() == before, "a partial apply was not rolled back"

        # Partial apply and the rollback fails: RECOVERY_REQUIRED, the live
        # options still differ, the originals stay on disk; recover fixes it.
        inject("partial", "fail")
        reply = gamemode("enable", ok=False)
        assert reply["state"] == "RECOVERY_REQUIRED" and not reply["enabled"], reply
        assert effective()["decoration:rounding"] == 0 and list(runtime.glob("cortetsu-gamemode-*.json"))
        assert gamemode("enable", ok=False)["state"] == "RECOVERY_REQUIRED"
        inject("fail")
        assert gamemode("recover", ok=False)["state"] == "RECOVERY_REQUIRED"
        assert gamemode("recover")["state"] == "INACTIVE"
        assert effective() == before

        # A restore fails on disable: kept for retry, the next disable ends it.
        gamemode("enable")
        inject("fail")
        assert gamemode("disable", ok=False)["state"] == "RECOVERY_REQUIRED"
        assert effective()["decoration:rounding"] == 0
        assert gamemode("disable")["state"] == "INACTIVE" and effective() == before

        # A quick on/off starts two helpers at once. Whatever order they run
        # in, ACTIVE holds exactly when the game values are live.
        for _ in range(6):
            racers = [subprocess.Popen(["python3", str(HELPER), action], env=env, stdout=subprocess.PIPE, text=True)
                      for action in ("enable", "disable")]
            for racer in racers:
                racer.communicate(timeout=30)
            if gamemode("status")["enabled"]:
                assert option("decoration:rounding") == 0, "ACTIVE reported but game values missing"
                gamemode("disable")
            assert effective() == before, "an interleaved enable/disable lost the user's values"

        # QML contract with the real helper on this Hyprland. The wrapper only
        # logs start/end (to catch overlapping helpers) and slows each run.
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
            '    IpcHandler { target: "harness"\n'
            '        function view(): string { return [GameMode.status, GameMode.enabled, GameMode.busy,'
            ' GameMode.needsRecovery].join(" ") }\n'
            '        function reload(): void { Quickshell.reload(false) } }\n}\n')
        fake = base / "fakebin"
        fake.mkdir()
        calls = base / "gamemode-calls"
        calls.touch()
        (fake / "notify-send").write_text(f"#!/bin/sh\necho \"$@\" >> {base}/notifications\n")
        (fake / "cortetsu-gamemode").write_text(f"""#!/bin/sh
echo "start $1" >> {calls}
sleep 0.3
python3 {HELPER} "$@"
code=$?
echo "end $1" >> {calls}
exit $code
""")
        for tool in fake.iterdir():
            tool.chmod(0o755)
        gamemode("enable")  # on before the shell starts: it must adopt it, not re-apply
        nested = dict(faulty, PATH=f"{fake}:{without_helper(env['PATH'])}", WAYLAND_DISPLAY=next(
            p.name for p in runtime.glob("wayland-*[0-9]")), QT_QPA_PLATFORM="wayland")
        log = (base / "qs.log").open("w")
        qs = subprocess.Popen(["qs", "-p", str(shell), "-n"], env=nested, stdout=log, stderr=subprocess.STDOUT,
                              start_new_session=True)
        try:
            def ipc(*args: str) -> str:
                return subprocess.run(["qs", "ipc", "--pid", str(qs.pid), "call", *args], env=nested, text=True,
                                      capture_output=True, timeout=10).stdout.strip()

            def runs() -> list[str]:
                return [line.split()[1] for line in calls.read_text().splitlines() if line.startswith("start")]

            def idle() -> bool:
                text = calls.read_text()
                return text.count("start") == text.count("end") and ipc("harness", "view").split()[2] == "false"

            def wait_view(expected: str, message: str) -> None:
                deadline = time.monotonic() + 20
                while ipc("harness", "view") != expected or not idle():
                    assert qs.poll() is None, (base / "qs.log").read_text()
                    assert time.monotonic() < deadline, f"{message}: {ipc('harness', 'view')} {calls.read_text()}"
                    time.sleep(0.1)

            assert shutil.which("cortetsu-gamemode", path=nested["PATH"]) == str(fake / "cortetsu-gamemode")
            wait_view("ACTIVE true false false", "the shell did not adopt ACTIVE from status")
            assert runs() == ["status"], "a starting shell must not re-apply game mode"

            # A QML reload asks status again and applies nothing.
            ipc("harness", "reload")
            deadline = time.monotonic() + 20
            while runs().count("status") < 2:
                ipc("harness", "view")  # singletons are created on first use, as the UI would
                assert time.monotonic() < deadline, f"no reload: {calls.read_text()}"
                time.sleep(0.1)
            wait_view("ACTIVE true false false", "reload lost the state")
            assert "enable" not in runs(), runs()

            ipc("gameMode", "disable")
            wait_view("INACTIVE false false false", "disable")
            assert effective() == before

            # The toggle shows "busy", never "on", while the helper is applying.
            ipc("gameMode", "enable")
            assert ipc("harness", "view").split()[1:3] == ["false", "true"], ipc("harness", "view")
            wait_view("ACTIVE true false false", "enable")
            ipc("gameMode", "disable")
            wait_view("INACTIVE false false false", "disable")

            # A rejected enable never reads as on and leaves Hyprland untouched.
            inject("fail")
            ipc("gameMode", "enable")
            wait_view("INACTIVE false false false", "a failed enable shows game mode on")
            assert effective() == before and runs()[-1] == "enable"
            assert "error" in (base / "notifications").read_text(), "the failure is reported"

            # Partial apply plus failed rollback: the UI offers recovery; the
            # toggle recovers instead of enabling, and Hyprland is restored.
            inject("partial", "fail")
            ipc("gameMode", "enable")
            wait_view("RECOVERY_REQUIRED false false true", "recovery state not shown")
            ipc("gameMode", "toggle")
            wait_view("INACTIVE false false false", "toggle did not recover")
            assert runs()[-1] == "disable" and effective() == before

            # Five quick toggles: helpers never overlap and the last request wins.
            for _ in range(5):
                ipc("gameMode", "toggle")
            wait_view("ACTIVE true false false", "odd number of toggles from off ends on")
            assert option("decoration:rounding") == 0
            depth = 0
            for line in calls.read_text().splitlines():
                depth += 1 if line.startswith("start") else -1
                assert depth <= 1, f"helpers overlapped: {calls.read_text()}"
            ipc("gameMode", "disable")
            wait_view("INACTIVE false false false", "final disable")

            # A helper that cannot start leaves the toggle UNKNOWN, not busy.
            (fake / "cortetsu-gamemode").rename(base / "parked")
            assert shutil.which("cortetsu-gamemode", path=nested["PATH"]) is None, "a real helper is reachable"
            ipc("gameMode", "enable")
            wait_view("UNKNOWN false false false", "a helper that never started kept the toggle busy")
            (base / "parked").rename(fake / "cortetsu-gamemode")
            ipc("gameMode", "disable")
            wait_view("INACTIVE false false false", "disable after UNKNOWN")
            assert effective() == before
            log_text = "\n".join(line for line in (base / "qs.log").read_text().splitlines()
                                  if "Process failed to start" not in line)  # the parked helper, on purpose
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

print("PASS: game mode is ACTIVE only after a verified apply, rolls back real partial applies, stays recoverable and keeps Settings changes")
