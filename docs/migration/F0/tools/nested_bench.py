#!/usr/bin/env python3
"""F0 nested baseline: shell start, surface open/close, 40-cycle soak, GameMode UNKNOWN.

    python3 scripts/integration/ws2_run.py --timeout 1500 OUT/nested.log -- \
        python3 docs/migration/F0/tools/nested_bench.py OUT [--starts 20] [--opens 10] [--cycles 40] [--hold 0]

Runs the shell composed from this checkout inside F0Session (isolated nested
Hyprland, see scripts/integration/f0_session.py) with 3 outputs; every
measurement happens on HEADLESS-1, which has its own frame clock.

- start: qs spawn -> "Configuration Loaded" in its log, and spawn -> the shell
  answering `drawers list` with its layers mapped (includes `qs ipc` polling).
- open/close: IPC call -> first HEADLESS-1 frame (grim, 1/4 scale) that differs
  from the settled closed frame; close -> frame equal to it again. Upper
  bounds: they include the `qs ipc` round trip and the capture interval,
  both reported.
- soak: N cycles opening and closing every surface; PSS/RSS, threads, fds and
  qs descendants sampled every 10 cycles, new QML warnings counted.
- gamemode: no cortetsu-gamemode on PATH (the helper cannot start) ->
  `gameMode status` must be UNKNOWN, and no real helper may have run.
- hold: keep the session alive for N seconds after the run, surfaces shown in
  turn, for watching WS 2.
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import statistics
import subprocess
import sys
import tempfile
import time

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO / "scripts/integration"))
from f0_session import F0Session  # noqa: E402

SURFACES = ("hardware", "display", "clipboard", "keyboards", "wallpapermanager", "overview", "calendar")


def stats(xs):
    if not xs:
        return {"n": 0}
    s = sorted(xs)
    return {"n": len(s), "p50_ms": round(statistics.median(s), 1),
            "p95_ms": round(s[max(0, round(0.95 * len(s)) - 1)], 1),
            "min_ms": round(s[0], 1), "max_ms": round(s[-1], 1),
            "stdev_ms": round(statistics.stdev(s), 1) if len(s) > 1 else 0.0}


def descendants(pid: int) -> list[int]:
    children = {}
    for entry in Path("/proc").iterdir():
        if entry.name.isdigit():
            try:
                ppid = int((entry / "stat").read_text().rsplit(")", 1)[1].split()[1])
            except (OSError, IndexError, ValueError):
                continue
            children.setdefault(ppid, []).append(int(entry.name))
    found, todo = [], [pid]
    while todo:
        for child in children.get(todo.pop(), []):
            found.append(child)
            todo.append(child)
    return found


def resources(pid: int) -> dict:
    proc = Path(f"/proc/{pid}")
    rollup = dict(re.findall(r"^(\w+):\s+(\d+) kB", (proc / "smaps_rollup").read_text(), re.M))
    status = dict(re.findall(r"^(\w+):\s+(\S+)", (proc / "status").read_text(), re.M))
    ticks = (proc / "stat").read_text().rsplit(")", 1)[1].split()
    kids = descendants(pid)
    return {"pss_mib": round(int(rollup["Pss"]) / 1024, 1), "rss_mib": round(int(rollup["Rss"]) / 1024, 1),
            "threads": int(status["Threads"]), "fds": len(os.listdir(proc / "fd")),
            "cpu_s": round((int(ticks[11]) + int(ticks[12])) / os.sysconf("SC_CLK_TCK"), 2),
            "descendants": len(kids),
            "descendant_cmds": sorted({(Path(f"/proc/{k}/comm").read_text().strip() if Path(f"/proc/{k}").exists() else "?")
                                       for k in kids})}


# Harness: expected from the isolation itself (no helpers in the temporary
# HOME, no clipboard history). Historical: also in the installed shell's
# journal on the real session (2026-10-20). Anything else is new.
WARNING_CLASSES = (
    ("harness", ("Process failed to start, likely because the binary could not be found",
                 "clipboard_history.json failed", "probe returned no reading")),
    ("historical", ("QWaylandTextInputv3::disableSurface", "QWaylandTextInputv3::enableSurface")),
)


def warning_class(line: str) -> str:
    return next((name for name, needles in WARNING_CLASSES if any(n in line for n in needles)), "other")


def qml_lines(path: Path) -> list[str]:
    return [re.sub(r"\x1b\[[0-9;]*m", "", line) for line in path.read_text(errors="replace").splitlines()
            if "WARN" in line or "ERROR" in line]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("out", type=Path)
    parser.add_argument("--starts", type=int, default=20)
    parser.add_argument("--opens", type=int, default=10)
    parser.add_argument("--cycles", type=int, default=40)
    parser.add_argument("--hold", type=float, default=0)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    result = {"date": time.strftime("%FT%T%z"),
              "head": subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"], text=True,
                                     capture_output=True).stdout.strip(),
              "dirty": bool(subprocess.run(["git", "-C", str(REPO), "status", "--porcelain"], text=True,
                                           capture_output=True).stdout.strip())}

    with tempfile.TemporaryDirectory(prefix="czf", dir="/tmp") as tmp:
        session = F0Session(Path(tmp))
        (session.base / "bin/cortetsu-gamemode").unlink(missing_ok=True)  # the helper cannot start: UNKNOWN path
        try:
            session.start(outputs=3)
            env = session.env()
            result["isolation"] = {k: env[k] for k in ("HOME", "XDG_RUNTIME_DIR", "XDG_CONFIG_HOME", "WAYLAND_DISPLAY",
                                                         "HYPRLAND_INSTANCE_SIGNATURE", "DBUS_SESSION_BUS_ADDRESS", "PATH")}
            result["isolation"]["nested_his_differs_from_desktop"] = (
                env["HYPRLAND_INSTANCE_SIGNATURE"] != os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"))
            result["isolation"]["shell_environ_runtime"] = (
                f"XDG_RUNTIME_DIR={session.runtime}".encode()
                in Path(f"/proc/{session.shell.pid}/environ").read_bytes().split(b"\0"))
            result["monitors"] = [m["name"] for m in session.monitors()]
            monitor = session.headless()[0]
            session.focus_monitor(monitor)
            grab = lambda: subprocess.run(["grim", "-o", monitor, "-s", "0.25", "-t", "ppm", "-"], env=env,
                                          capture_output=True, timeout=5).stdout
            ipc_ms, grab_ms = [], []

            def call(target, method):
                t0 = time.perf_counter()
                r = session.ipc(target, method)
                ipc_ms.append((time.perf_counter() - t0) * 1000)
                return r

            def settled(timeout=4.0):
                previous, deadline = grab(), time.monotonic() + timeout
                while time.monotonic() < deadline:
                    t0 = time.perf_counter()
                    frame = grab()
                    grab_ms.append((time.perf_counter() - t0) * 1000)
                    if frame == previous:
                        return frame
                    previous = frame
                return None

            # GameMode with no helper on PATH.
            time.sleep(1.5)
            result["gamemode"] = {"status_without_helper": session.ipc("gameMode", "status").stdout.strip()}

            # open/close latency
            opens = {}
            for target in SURFACES:
                o, c, diag = [], [], {"unsettled": 0, "no_change": 0, "not_open": 0, "not_restored": 0}
                for _ in range(args.opens):
                    call(target, "close")
                    closed = settled()
                    if closed is None:
                        diag["unsettled"] += 1
                        continue
                    t0 = time.perf_counter()
                    call(target, "open")
                    while time.perf_counter() - t0 < 3 and grab() == closed:
                        pass
                    opened_ms = (time.perf_counter() - t0) * 1000
                    if opened_ms >= 3000:
                        diag["no_change"] += 1
                        continue
                    o.append(opened_ms)
                    if session.ipc(target, "isOpen").stdout.strip() != "true":
                        diag["not_open"] += 1
                    settled()
                    t1 = time.perf_counter()
                    call(target, "close")
                    while time.perf_counter() - t1 < 3 and grab() != closed:
                        pass
                    closed_ms = (time.perf_counter() - t1) * 1000
                    if closed_ms < 3000:
                        c.append(closed_ms)
                    else:
                        diag["not_restored"] += 1
                opens[target] = {"open_first_changed_frame": stats(o), "close_frame_restored": stats(c), "diag": diag}
            result["surfaces"] = opens
            result["ipc_roundtrip"] = stats(ipc_ms)
            result["grim_capture"] = stats(grab_ms)

            # shell starts (fresh process each time)
            qs_log = session.logs / "qs.log"
            ready, loaded = [], []
            for _ in range(args.starts):
                session.stop_shell()
                times = session.start_shell()
                ready.append(times["ready_ms"])
                loaded.append(times["loaded_ms"])
            result["shell_start_configuration_loaded"] = stats(loaded)
            result["shell_start_ready"] = stats(ready)
            session.focus_monitor(monitor)
            time.sleep(2)

            # soak
            startup_warnings = len(qml_lines(qs_log))
            soak = [dict(cycle=0, **resources(session.shell.pid))]
            failures = []
            for cycle in range(1, args.cycles + 1):
                for target in SURFACES:
                    session.ipc(target, "open")
                    time.sleep(0.25)
                    if session.ipc(target, "isOpen").stdout.strip() != "true":
                        failures.append((cycle, target, "open"))
                    session.ipc(target, "close")
                    time.sleep(0.15)
                    if session.ipc(target, "isOpen").stdout.strip() != "false":
                        failures.append((cycle, target, "close"))
                if cycle % 10 == 0:
                    soak.append(dict(cycle=cycle, **resources(session.shell.pid)))
            soak_lines = qml_lines(qs_log)[startup_warnings:]
            counts = {}
            for line in soak_lines:
                key = re.sub(r"0x[0-9a-f]+|\d+", "N", line.split("]", 1)[-1].strip())[:160]
                counts[key] = counts.get(key, 0) + 1
            result["soak"] = {"cycles": args.cycles, "surfaces": list(SURFACES), "samples": soak,
                              "state_failures": failures, "new_qml_warnings": len(soak_lines),
                              "new_qml_warning_classes": {c: sum(warning_class(l) == c for l in soak_lines)
                                                          for c in ("harness", "historical", "other")},
                              "new_qml_warning_kinds": counts}
            result["qml_startup_warning_kinds"] = sorted({re.sub(r"0x[0-9a-f]+|/tmp/\S+|\d+", "N",
                                                                 line.split("]", 1)[-1].strip())[:160]
                                                          for line in qml_lines(qs_log)})

            for target in SURFACES:  # visual evidence
                session.ipc(target, "open")
                time.sleep(0.8)
                subprocess.run(["grim", "-o", monitor, str(args.out / f"surface-{target}.png")], env=env)
                session.ipc(target, "close")
                time.sleep(0.3)
            deadline = time.monotonic() + args.hold
            while time.monotonic() < deadline:
                for target in SURFACES:
                    session.ipc(target, "open")
                    time.sleep(min(6, max(0, deadline - time.monotonic())))
                    session.ipc(target, "close")
                    if time.monotonic() >= deadline:
                        break

            calls = session.stub_calls.read_text().splitlines()
            result["stub_calls"] = {name: sum(line.split()[0] == name for line in calls)
                                    for name in sorted({line.split()[0] for line in calls})}
            result["gamemode"]["helper_calls_recorded"] = result["stub_calls"].get("cortetsu-gamemode", 0)
            result["hyprctl_binds_count"] = len(session.hjson("binds") or [])
            (args.out / "qs.log").write_text(qs_log.read_text(errors="replace"))
            (args.out / "hyprland.log").write_text((session.logs / "hyprland.log").read_text(errors="replace"))
        finally:
            session.stop()
            pids = session.sweep()
            result["cleanup"] = {"leftover_pids_after_stop": pids,
                                 "runtime_dir_removed": not session.runtime.exists()}
    (args.out / "nested-bench.json").write_text(json.dumps(result, indent=1, ensure_ascii=False))
    print(json.dumps({k: v for k, v in result.items() if k not in ("qml_startup_warning_kinds",)}, indent=1,
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
