#!/usr/bin/env python3
"""Does the F1a debug procedure move the active workspace? Measured on a stand-in desktop.

    python3 scripts/integration/ws2_run.py LOG -- python3 docs/migration/F1a/tools/ws_repro.py OUT_DIR [COMMAND...]

A nested Hyprland plays the desktop: two outputs, focus_on_activate = true (as
in dotfiles misc.lua), a terminal focused on WS 3. ws_watch.py records its
active workspace and monitor. Then, one at a time, each step the F1a session
ran against the real desktop:

  shim     ws2_run.py starting a nested Hyprland (the shim's exec_cmd "2 silent")
  debug    the debug Kitty: exec_cmd("kitty …", { workspace = "2 silent" })

With COMMAND, that command is the only step: it runs with the stand-in as
its desktop (HYPRLAND_INSTANCE_SIGNATURE, XDG_RUNTIME_DIR, WAYLAND_DISPLAY).

Writes OUT_DIR/events.jsonl and OUT_DIR/result.json with the active workspace
and monitor before, during and after each step. The real desktop only receives
the stand-in's own window (on WS 2 when run under ws2_run.py).
"""
import json, os, shutil, signal, subprocess, sys, tempfile, time
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO / "scripts/integration"))
from nested_gpu import MESA_ONLY, compositor_env  # noqa: E402

out = Path(sys.argv[1]).resolve()
out.mkdir(parents=True, exist_ok=True)
base = Path(tempfile.mkdtemp(prefix="cz-wsrepro-"))
runtime = Path(tempfile.mkdtemp(prefix="czw", dir="/tmp"))  # short: see launcher_harness.Session
home = base / "home"
(home / ".config/hypr").mkdir(parents=True)
(home / ".config/hypr/hyprland.lua").write_text(
    'hl.config({ misc = { focus_on_activate = true, disable_hyprland_logo = true }, animations = { enabled = false } })\n'
    'hl.monitor({ output = "WAYLAND-1", mode = "preferred", position = "0x0", scale = 1 })\n'
    'hl.monitor({ output = "HEADLESS-1", mode = "1280x720", position = "auto-right", scale = 1 })\n'
    'hl.device({ name = "wl_keyboard", enabled = false })\n'
    'hl.device({ name = "wl_pointer", enabled = false })\n')
parent = os.environ["WAYLAND_DISPLAY"]
parent = parent if parent.startswith("/") else f"{os.environ['XDG_RUNTIME_DIR']}/{parent}"
procs = []


def wait(pred, what, timeout=30):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        v = pred()
        if v:
            return v
        time.sleep(0.1)
    raise SystemExit(f"timeout: {what}")


def spawn(cmd, env, **kw):
    p = subprocess.Popen(cmd, env=env, start_new_session=True, stdout=kw.pop("stdout", subprocess.DEVNULL),
                         stderr=subprocess.STDOUT, **kw)
    procs.append(p)
    return p


env = {"HOME": str(home), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
       "WAYLAND_DISPLAY": parent}
try:
    spawn(["Hyprland"], compositor_env(env, base), cwd=base, stdout=(base / "desk.log").open("w"))
    sig = wait(lambda: (runtime / "hypr").is_dir() and next((p.name for p in (runtime / "hypr").iterdir()), None), "desk IPC")
    sock = wait(lambda: next((p.name for p in runtime.glob("wayland-*[0-9]")), None), "desk socket")
    desk = {**os.environ, **MESA_ONLY, "HYPRLAND_INSTANCE_SIGNATURE": sig, "XDG_RUNTIME_DIR": str(runtime),
            "WAYLAND_DISPLAY": sock, "HOME": str(home)}
    for k in ("XDG_ACTIVATION_TOKEN", "DESKTOP_STARTUP_ID"):
        desk.pop(k, None)
    hy = lambda *a: subprocess.run(["/usr/bin/hyprctl", *a], env=desk, capture_output=True, text=True, timeout=10).stdout
    j = lambda w: json.loads(hy(w, "-j") or "null")
    wait(lambda: hy("output", "create", "headless") is not None and len(j("monitors") or []) == 2, "two outputs")
    # WS 2 hidden, as on a one-monitor desktop: the second output shows WS 4.
    hy("dispatch", 'hl.dsp.focus({ monitor = "HEADLESS-1" })')
    hy("dispatch", 'hl.dsp.focus({ workspace = "4" })')
    # The user's terminal: focused, on WS 3 of the first output.
    hy("dispatch", 'hl.dsp.focus({ monitor = "WAYLAND-1" })')
    hy("dispatch", 'hl.dsp.focus({ workspace = "3" })')
    spawn(["kitty", "--config", "NONE", "--class", "user-term", "sleep", "infinity"], desk)
    wait(lambda: (j("activewindow") or {}).get("class") == "user-term", "user terminal focused")
    events = out / "events.jsonl"
    events.unlink(missing_ok=True)
    watch = spawn([sys.executable, "-I", str(Path(__file__).with_name("ws_watch.py")), str(events),
                   "--signature", sig, "--runtime", str(runtime)], desk)
    time.sleep(1)
    state = lambda: {"ws": (j("activeworkspace") or {}).get("id"),
                     "monitor": next((m["name"] for m in j("monitors") or [] if m["focused"]), None),
                     "window": (j("activewindow") or {}).get("class")}
    kitty_sock = f"unix:@cz-wsrepro-{os.getpid()}"
    steps = {
        # The real ws2_run.py, pointed at the stand-in desktop, starting one
        # nested Hyprland that lives 6 s (as a nested test does).
        "shim": [sys.executable, str(REPO / "scripts/integration/ws2_run.py"), "--timeout", "120", str(out / "shim.log"),
                 "--", "sh", "-c", f"cd {base} && timeout 6 Hyprland --config {base}/inner.lua; true"],
        # docs/migration/F0/DEBUG-SESSION.md §2, as run, but a socket of its own.
        "debug": ["/usr/bin/hyprctl", "dispatch", f'hl.dsp.exec_cmd("kitty --config NONE --class cortetsu-f1a-debug '
                  f'-o allow_remote_control=socket-only --listen-on {kitty_sock} sleep 60", {{ workspace = "2 silent" }})'],
        # §2 again: an observation tab opened by remote control, as F0 and F1a did.
        "tab": ["kitty", "@", "--to", kitty_sock, "launch", "--type=tab", "--tab-title", "logs", "sleep", "30"],
        # The same tab, asking kitty not to take focus.
        "tab_keep_focus": ["kitty", "@", "--to", kitty_sock, "launch", "--type=tab", "--keep-focus", "--tab-title", "procs",
                           "sleep", "30"],
    }
    if sys.argv[2:]:  # any other command, e.g. the whole suite under ws2_run.py, run inside the stand-in
        steps = {"command": sys.argv[2:]}
    (base / "inner.lua").write_text('hl.config({ misc = { disable_hyprland_logo = true } })\n')
    result = {}
    for name, cmd in steps.items():
        before = state()
        t0 = time.monotonic()
        p = subprocess.Popen(cmd, env=desk, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
        during = []
        while time.monotonic() - t0 < 10 or p.poll() is None:
            during.append(state())
            time.sleep(0.25)
        time.sleep(1.5)
        after = state()
        seen = sorted({(d["ws"], d["monitor"], d["window"]) for d in during}, key=str)
        result[name] = {"before": before, "during_distinct": [dict(zip(("ws", "monitor", "window"), s)) for s in seen],
                        "after": after, "rc": p.returncode, "t0": round(t0, 3), "ws_moved": any(d["ws"] != before["ws"] for d in during + [after])}
        print(name, json.dumps(result[name]), flush=True)
        # Put the stand-in back on WS 3 only between steps, so each step starts equal.
        hy("dispatch", 'hl.dsp.focus({ workspace = "3" })')
        time.sleep(1)
    watch.send_signal(signal.SIGTERM)
    watch.wait(5)
    (out / "result.json").write_text(json.dumps(result, indent=1))
finally:
    for p in reversed(procs):
        if p.poll() is None:
            try:
                os.killpg(p.pid, signal.SIGTERM)
                p.wait(10)
            except (ProcessLookupError, subprocess.TimeoutExpired):
                pass
    shutil.rmtree(runtime, ignore_errors=True)
    shutil.rmtree(base, ignore_errors=True)
