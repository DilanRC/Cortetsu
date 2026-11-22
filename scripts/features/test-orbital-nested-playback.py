#!/usr/bin/env python3
"""Orbital plays a real animated wallpaper in a nested Hyprland.

The installed supervisor (`cortetsu-desktop-runtime cortetsu-orbital
session`) runs against a private nested Hyprland, with its own runtime and
state, and drives linux-wallpaperengine on that compositor's only output:

1. the snapshot names the nested output and the Almamu backend;
2. apply waits for the cover (this script answers `covered` as Background.qml
   would), the renderer maps its own layer surface on that output, and only
   then the output turns `active` (never before the surface);
3. a second apply while one is in flight is refused as `busy`;
4. stop returns the output to `stopped` and the renderer's surface goes;
5. closing stdin ends the supervisor and its renderer (no orphan).

Uses the first local Workshop project of each type it is given; nothing is
downloaded and Steam's folders are only read. Rendering is pinned to Mesa
(nested_gpu) so a suspended NVIDIA GPU stays asleep. Opens a nested window:
run it on a free workspace (scripts/integration/ws2_run.py) or with the
desktop idle.

    test-orbital-nested-playback.py [PROJECT_DIR...]
"""
from __future__ import annotations

import json
import os
import queue
import subprocess
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "integration"))
from nested_gpu import MESA_ONLY, compositor_env  # noqa: E402

WORKSHOP = Path.home() / ".local/share/Steam/steamapps/workshop/content/431960"
# The supervisor finds them under HOME, which is private here.
ASSETS = Path.home() / ".local/share/Steam/steamapps/common/wallpaper_engine/assets"
CONFIG = 'hl.config({ animations = { enabled = false } })\n'


def runtime_binary() -> Path:
    builds = sorted((Path.home() / ".local/share/cortetsu/helpers/builds").glob("helpers-[0-9a-f]*"),
                    key=lambda path: path.stat().st_mtime)
    for build in reversed(builds):
        candidate = build / "cortetsu-desktop-runtime"
        if candidate.is_file():
            return candidate
    raise SystemExit("SKIP: no installed cortetsu-desktop-runtime")


def project_of(kind: str) -> Path | None:
    for project in sorted(WORKSHOP.glob("*/project.json")):
        try:
            if str(json.loads(project.read_text(errors="replace")).get("type", "")).lower() == kind:
                return project.parent
        except ValueError:
            continue
    return None


def main() -> int:
    if not os.environ.get("WAYLAND_DISPLAY"):
        print("SKIP: requiere una sesión Wayland para anidar Hyprland")
        return 0
    projects = [Path(arg) for arg in sys.argv[1:]] or [p for p in (project_of("video"), project_of("scene")) if p]
    if not projects:
        print("SKIP: no local Workshop project")
        return 0
    binary = runtime_binary()
    failures: list[str] = []

    def check(condition: bool, message: str) -> None:
        if not condition:
            failures.append(message)
            print("FAIL:", message, flush=True)

    with tempfile.TemporaryDirectory(prefix="czo", dir="/tmp") as tmp:
        base = Path(tmp)
        runtime = base / "r"
        runtime.mkdir(mode=0o700)
        (base / "cfg/hypr").mkdir(parents=True)
        (base / "cfg/hypr/hyprland.lua").write_text(CONFIG)
        parent = os.environ["WAYLAND_DISPLAY"]
        parent = parent if parent.startswith("/") else str(Path(os.environ["XDG_RUNTIME_DIR"]) / parent)
        env = {"HOME": str(base), "PATH": os.environ["PATH"], "LANG": "C.UTF-8", "XDG_RUNTIME_DIR": str(runtime),
               "XDG_CONFIG_HOME": str(base / "cfg"), "XDG_STATE_HOME": str(base / "state")}
        compositor = subprocess.Popen(["Hyprland"], cwd=base, env=compositor_env(dict(env, WAYLAND_DISPLAY=parent), base),
                                      stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
        supervisor = None
        try:
            deadline = time.monotonic() + 20
            while time.monotonic() < deadline and not (runtime / "hypr").is_dir():
                time.sleep(0.1)
            time.sleep(1)
            env["HYPRLAND_INSTANCE_SIGNATURE"] = next((runtime / "hypr").iterdir()).name
            env["WAYLAND_DISPLAY"] = next(p.name for p in runtime.iterdir() if p.name.startswith("wayland-") and not p.name.endswith(".lock"))
            env.update(MESA_ONLY)

            def layers() -> list[tuple[str, str, int]]:
                out = subprocess.run(["hyprctl", "layers", "-j"], env=env, text=True, capture_output=True, timeout=10).stdout
                found = []
                for monitor, data in json.loads(out or "{}").items():
                    for level, items in data.get("levels", {}).items():
                        for item in items:
                            found.append((monitor, item.get("namespace", ""), item.get("pid", 0)))
                return found

            # A private session bus: the renderer needs one, as on the desktop.
            # A damaged or newer orbital.json stops the supervisor with a
            # reason and is never rewritten.
            state_dir = base / "state" / "cortetsu"
            state_dir.mkdir(parents=True, exist_ok=True)
            for name, body in (("corrupt", "{not json"), ("version", '{"version": 99}'), ("unknown field", '{"version": 1, "surprise": true}')):
                (state_dir / "orbital.json").write_text(body)
                run = subprocess.run(["dbus-run-session", "--", str(binary), "cortetsu-orbital", "session"], env=env,
                                     input="", text=True, capture_output=True, timeout=15)
                check(run.returncode != 0 and "preserved" in run.stderr + run.stdout,
                      f"orbital.json {name}: the supervisor did not stop with a reason ({run.returncode}: {run.stderr.strip()[:160]})")
                check((state_dir / "orbital.json").read_text() == body, f"orbital.json {name} was rewritten")
            (state_dir / "orbital.json").unlink()
            print("OK persistence: damaged, newer and unknown files stop the supervisor and stay intact", flush=True)

            supervisor = subprocess.Popen(["dbus-run-session", "--", str(binary), "cortetsu-orbital", "session"], env=env, cwd=base,
                                          stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                          text=True, bufsize=1, start_new_session=True)
            events: queue.Queue = queue.Queue()
            threading.Thread(target=lambda: [events.put(json.loads(line)) for line in supervisor.stdout
                                             if line.strip().startswith("{")], daemon=True).start()

            def send(value: dict) -> None:
                supervisor.stdin.write(json.dumps(value) + "\n")
                supervisor.stdin.flush()

            last: dict = {}

            def wait(test, seconds: float, beat: bool = True) -> dict | None:
                end = time.monotonic() + seconds
                while time.monotonic() < end:
                    try:
                        event = events.get(timeout=0.5)
                    except queue.Empty:
                        if beat:
                            send({"op": "heartbeat"})
                        continue
                    if event.get("event") == "snapshot":
                        last.clear()
                        last.update(event)
                    elif os.environ.get("ORBITAL_TRACE"):
                        print("event", json.dumps(event)[:300], flush=True)
                    if event.get("event") == "error" and event.get("code") != "busy":
                        print("supervisor error:", event.get("code"), event.get("message"), flush=True)
                    if test(event):
                        return event
                return None

            snapshot = wait(lambda e: e.get("event") == "snapshot", 10)
            check(snapshot is not None, "no initial snapshot")
            outputs = snapshot["outputs"] if snapshot else {}
            monitor = next(iter(outputs)) if isinstance(outputs, dict) and outputs else None
            check(monitor is not None, f"the nested output is not listed: {outputs}")

            def output() -> dict:
                return (last.get("outputs") or {}).get(monitor, {})

            for project in projects:
                kind = json.loads((project / "project.json").read_text(errors="replace")).get("type", "?")
                send({"op": "apply", "monitor": monitor, "selection": {"location": str(project), "muted": True,
                                                                       "fps": 15, "gpu": "integrated", "assets": str(ASSETS)}})
                preparing = wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "preparing", 10)
                check(preparing is not None, f"{kind}: apply never entered preparing ({output()})")
                send({"op": "apply", "monitor": monitor, "selection": {"location": str(project), "assets": str(ASSETS)}})
                busy = wait(lambda e: e.get("event") == "error" and e.get("code") == "busy", 5)
                check(busy is not None, f"{kind}: a second apply in flight was not refused as busy")
                send({"op": "covered", "monitor": monitor, "generation": output().get("generation")})
                # The renderer maps; then, as Background.qml does, lift the cover.
                wait(lambda e: e.get("event") == "snapshot" and output().get("state") in ("applying", "error"), 20)
                check(output().get("state") == "applying", f"{kind}: the renderer's surface was not seen ({output().get('state')})")
                send({"op": "revealed", "monitor": monitor, "generation": output().get("generation")})
                active = wait(lambda e: e.get("event") == "snapshot" and output().get("state") in ("active", "error"), 25)
                if os.environ.get("ORBITAL_TRACE"):
                    print("trace layers", layers(), "pid", output().get("pid"), flush=True)
                    print("trace procs", subprocess.run(["pgrep", "-af", "linux-wallpaperengine"], text=True, capture_output=True).stdout, flush=True)
                phase = output().get("state")
                renderer = [l for l in layers() if l[1] == "linux-wallpaperengine"]
                if phase == "active":
                    check(len(renderer) == 1, f"{kind}: active without exactly one renderer surface ({renderer})")
                    print(f"OK {kind} {project.name}: active, surface mapped on {renderer[0][0]}", flush=True)
                else:
                    check(False, f"{kind} {project.name}: {phase} {output().get('error')}")
                send({"op": "stop", "monitor": monitor})
                send({"op": "covered", "monitor": monitor, "generation": output().get("generation")})
                wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "stopped", 10)
                time.sleep(1.5)
                check(output().get("state") == "stopped", f"{kind}: stop left {output().get('state')}")
                if os.environ.get("ORBITAL_TRACE"):
                    print("trace after stop", layers(), subprocess.run(["pgrep", "-af", "linux-wallpaperengine"], text=True, capture_output=True).stdout, flush=True)
                gone = time.monotonic() + 5
                while time.monotonic() < gone and [l for l in layers() if l[1] == "linux-wallpaperengine"]:
                    time.sleep(0.25)
                check(not [l for l in layers() if l[1] == "linux-wallpaperengine"], f"{kind}: the renderer outlived stop")
                check(not renderer or not Path(f"/proc/{renderer[0][2]}").exists()
                      or "Z" in Path(f"/proc/{renderer[0][2]}/stat").read_text().split()[2], f"{kind}: the renderer process is still running")

            def play(project: Path) -> bool:
                send({"op": "apply", "monitor": monitor, "selection": {"location": str(project), "muted": True, "fps": 15,
                                                                       "gpu": "integrated", "assets": str(ASSETS)}})
                wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "preparing", 10)
                send({"op": "covered", "monitor": monitor, "generation": output().get("generation")})
                wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "applying", 20)
                send({"op": "revealed", "monitor": monitor, "generation": output().get("generation")})
                return wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "active", 10) is not None

            # kill -9 of the renderer: restarted twice within 120 s, then an
            # error and the static wallpaper. Only our own renderer's PID.
            check(play(projects[0]), "could not start the renderer for the crash test")
            for attempt in (1, 2, 3):
                pid = output().get("pid")
                check(bool(pid), f"crash {attempt}: no renderer PID")
                if not pid:
                    break
                os.kill(pid, 9)
                if attempt < 3:
                    # The restart is a new apply: cover, renderer, reveal.
                    back = wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "preparing", 20)
                    check(back is not None, f"crash {attempt}: the renderer was not restarted ({output()})")
                    send({"op": "covered", "monitor": monitor, "generation": output().get("generation")})
                    wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "applying", 20)
                    send({"op": "revealed", "monitor": monitor, "generation": output().get("generation")})
                    again = wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "active", 10)
                    check(again is not None and output().get("restarts") == attempt,
                          f"crash {attempt}: not active again with {attempt} restart(s) ({output()})")
                else:
                    failed = wait(lambda e: e.get("event") == "snapshot" and output().get("state") == "error", 20)
                    check(failed is not None and "restart limit" in str(output().get("error")),
                          f"the third crash did not end in the restart-limit error ({output()})")
            if not [f for f in failures if f.startswith("crash") or "third crash" in f]:
                print("OK crash: two restarts, then the restart-limit error", flush=True)

            # Another client presenting the wallpaper: refused, and left alone.
            # Launched the way a user or another tool would, not through Orbital.
            almamu = Path("/opt/linux-wallpaperengine")
            foreign = subprocess.Popen(["dbus-run-session", "--", str(almamu / "linux-wallpaperengine"),
                                        "--screen-root", monitor, "--bg", str(projects[0]), "--layer", "background",
                                        "--fps", "5", "--hwdec", "no", "--silent", "--disable-mouse", "--assets-dir", str(ASSETS)],
                                       env=dict(env, LD_LIBRARY_PATH=str(almamu / "lib"), XDG_SESSION_TYPE="wayland"), cwd=almamu,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            try:
                seen = time.monotonic() + 20
                # Its surface: the engine's namespace, not a PID of the supervisor's.
                def theirs():
                    return [l for l in layers() if l[1] == "linux-wallpaperengine"]
                while time.monotonic() < seen and not theirs():
                    time.sleep(0.5)
                check(bool(theirs()), "the foreign renderer never mapped")
                send({"op": "apply", "monitor": monitor, "selection": {"location": str(projects[0]), "assets": str(ASSETS)}})
                refused = wait(lambda e: e.get("event") == "error" and e.get("code") == "foreign-owner", 10)
                check(refused is not None, "a foreign owner was not refused")
                check(output().get("state") != "preparing", "the supervisor began a transition over a foreign owner")
                time.sleep(1)
                check(foreign.poll() is None and bool(theirs()), "the supervisor touched the foreign renderer")
                if not [f for f in failures if "foreign" in f]:
                    print("OK foreign owner: refused, its process untouched", flush=True)
            finally:
                # Its own session (start_new_session): the group is ours alone.
                os.killpg(foreign.pid, 9)
                foreign.wait(timeout=10)
            gone = time.monotonic() + 5
            while time.monotonic() < gone and [l for l in layers() if l[1] == "linux-wallpaperengine"]:
                time.sleep(0.25)

            # A monitor that goes away while playing gets its wallpaper back
            # when it returns in the same session (a virtual output here).
            if play(projects[0]):
                hyprctl_out = lambda *args: subprocess.run(["hyprctl", "output", *args], env=env, capture_output=True, text=True, timeout=10)
                created = hyprctl_out("create", "headless", "QA-1").returncode == 0
                if created:
                    end = time.monotonic() + 10
                    while time.monotonic() < end and "QA-1" not in (last.get("outputs") or {}):
                        wait(lambda e: e.get("event") == "snapshot", 3)
                    # restoreOnStart off, as after a Stop: coming back in the
                    # session must not depend on it.
                    send({"op": "apply", "monitor": "QA-1", "selection": {"location": str(projects[0]), "muted": True, "fps": 15, "gpu": "integrated", "assets": str(ASSETS), "restoreOnStart": False}})
                    other = lambda: (last.get("outputs") or {}).get("QA-1", {})
                    wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "preparing", 10)
                    send({"op": "covered", "monitor": "QA-1", "generation": other().get("generation")})
                    wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "applying", 20)
                    send({"op": "revealed", "monitor": "QA-1", "generation": other().get("generation")})
                    wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "active", 10)
                    check(other().get("state") == "active", f"the second output did not play ({other()})")
                    hyprctl_out("remove", "QA-1")
                    wait(lambda e: e.get("event") == "snapshot" and "QA-1" not in (last.get("outputs") or {}), 15)
                    check(output().get("state") == "active", "removing the second output touched the first")
                    hyprctl_out("create", "headless", "QA-1")
                    back = wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "preparing", 20)
                    check(back is not None, f"a returning output did not get its wallpaper back ({other()})")
                    if back:
                        send({"op": "covered", "monitor": "QA-1", "generation": other().get("generation")})
                        wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "applying", 20)
                        send({"op": "revealed", "monitor": "QA-1", "generation": other().get("generation")})
                        wait(lambda e: e.get("event") == "snapshot" and other().get("state") == "active", 10)
                        check(other().get("state") == "active", f"the returning output is not playing ({other()})")
                    hyprctl_out("remove", "QA-1")
                    if not [f for f in failures if "output" in f]:
                        print("OK reconnect: a returning output plays its wallpaper again; the other is untouched", flush=True)
                else:
                    print("SKIP reconnect: this Hyprland cannot create a virtual output", flush=True)

            # EOF: the supervisor leaves and takes its renderers with it.
            play(projects[0])
            own = output().get("pid")
            check(output().get("state") == "active" and bool(own), f"the last apply did not play ({output()})")
            supervisor.stdin.close()
            supervisor.wait(timeout=10)
            gone = time.monotonic() + 5
            while time.monotonic() < gone and [l for l in layers() if l[1] == "linux-wallpaperengine"]:
                time.sleep(0.25)
            check(not [l for l in layers() if l[1] == "linux-wallpaperengine"], "a renderer surface survived the supervisor")
            check(not own or not Path(f"/proc/{own}").exists() or "Z" in Path(f"/proc/{own}/stat").read_text().split()[2],
                  "the renderer process survived the supervisor")
        finally:
            if supervisor and supervisor.poll() is None:
                supervisor.kill()
            if supervisor and supervisor.stderr:
                tail = supervisor.stderr.read()[-2000:]
                if tail.strip():
                    print("supervisor stderr:", tail, flush=True)
            compositor.terminate()
            try:
                compositor.wait(timeout=10)
            except subprocess.TimeoutExpired:
                compositor.kill()
    if failures:
        print(f"FAIL: {len(failures)} Orbital playback checks")
        return 1
    print(f"PASS: Orbital plays {', '.join(p.name for p in projects)} in a nested Hyprland: cover first, one renderer surface, busy refused, two crash restarts then the limit, a returning output restored, a foreign owner refused and left alone, damaged or newer preferences kept, stop and EOF leave nothing behind")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
