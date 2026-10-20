#!/usr/bin/env python3
"""Resident cost of the Cortetsu user units over a window: CPU from cgroup
CPUUsageNSec deltas, MemoryCurrent, per-process RSS/PSS (smaps_rollup), and
distinct PIDs seen in each cgroup (sampled every 50 ms: very short-lived
children can be missed, so this is a lower bound on spawns).
Usage: python3 -I bench_resident.py SECONDS RUNS out.json   (read-only)"""
import json, subprocess, sys, time
from pathlib import Path
SEC, RUNS, OUT = float(sys.argv[1]), int(sys.argv[2]), sys.argv[3]
UNITS = ["cortetsu-shell.service", "cortetsu-power-auto.service", "cortetsu-wallpaper-color.service"]
def show(u):
    r = subprocess.run(["systemctl", "--user", "show", u, "-p", "CPUUsageNSec,MemoryCurrent,ControlGroup,MainPID,ActiveEnterTimestampMonotonic,ExecMainStartTimestamp"], capture_output=True, text=True).stdout
    return dict(l.split("=", 1) for l in r.splitlines() if "=" in l)
def procs(cg):
    p = Path("/sys/fs/cgroup") / cg.lstrip("/") / "cgroup.procs"
    try: return set(int(x) for x in p.read_text().split())
    except OSError: return set()
def mem(pid):
    d = {}
    try:
        for l in Path(f"/proc/{pid}/smaps_rollup").read_text().splitlines():
            k, *v = l.split()
            if k in ("Rss:", "Pss:"): d[k[:-1].lower() + "_mib"] = round(int(v[0]) / 1024, 1)
        d["comm"] = Path(f"/proc/{pid}/comm").read_text().strip()
    except OSError: pass
    return d
runs = []
for i in range(RUNS):
    s0 = {u: show(u) for u in UNITS}
    seen = {u: set() for u in UNITS}
    t0 = time.monotonic()
    while time.monotonic() - t0 < SEC:
        for u in UNITS: seen[u] |= procs(s0[u]["ControlGroup"])
        time.sleep(0.05)
    el = time.monotonic() - t0
    s1 = {u: show(u) for u in UNITS}
    r = {}
    for u in UNITS:
        cpu = (int(s1[u]["CPUUsageNSec"]) - int(s0[u]["CPUUsageNSec"])) / 1e9
        now = procs(s1[u]["ControlGroup"])
        r[u] = {"cpu_s": round(cpu, 3), "cpu_pct_one_core": round(100 * cpu / el, 2),
                "memory_current_mib": round(int(s1[u]["MemoryCurrent"]) / 2**20, 1),
                "pids_seen": len(seen[u]), "pids_resident_end": len(now),
                "transient_pids": len(seen[u] - now - procs(s0[u]["ControlGroup"])),
                "procs": {p: mem(p) for p in sorted(now)}, "main_pid": s1[u]["MainPID"], "started": s1[u]["ExecMainStartTimestamp"]}
    runs.append({"elapsed_s": round(el, 1), "loadavg_end": open("/proc/loadavg").read().split()[:3], "units": r})
    print(f"run {i+1}: " + "  ".join(f"{u.split('.')[0]} cpu={r[u]['cpu_pct_one_core']}% mem={r[u]['memory_current_mib']}MiB transient={r[u]['transient_pids']}" for u in UNITS), flush=True)
dg = {d.name: (d/"power/runtime_status").read_text().strip() for d in Path("/sys/bus/pci/devices").iterdir() if (d/"vendor").read_text().strip() == "0x10de"}
json.dump({"date": time.strftime("%FT%T%z"), "window_s": SEC, "dgpu_end": dg, "runs": runs}, open(OUT, "w"), indent=1)
