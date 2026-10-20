#!/usr/bin/env python3
"""Wall latency P50/P95 of read-only helper invocations, as the shell runs them.
Usage: python3 -I bench_latency.py N out.json. It does not refuse a run: it
records in meta whether the dGPU woke (dgpu_before/after) and which watched
state files changed (state_changed_during_run). power-auto-control status
rewrites its config on every call (RISKS.md F-04), so that list is never empty;
check it for anything beyond the known entries before trusting a run."""
import json, os, statistics, subprocess, sys, time
from pathlib import Path
N = int(sys.argv[1]); out = sys.argv[2]
H = Path.home()
CMDS = {
 "python3 -c pass (interpreter floor)": ["python3", "-c", "pass"],
 "cortetsu-gamemode status": ["cortetsu-gamemode", "status"],
 "cortetsu-keybinds list (Rust)": ["cortetsu-keybinds", "list"],
 "cortetsu-scheme list": ["cortetsu-scheme", "list"],
 "cortetsu-record status": ["cortetsu-record", "status"],
 "cortetsu-display-probe": ["cortetsu-display-probe"],
 "cortetsu-hardware-probe": ["cortetsu-hardware-probe"],
 "cortetsu-power-auto-control status": ["cortetsu-power-auto-control", "status"],
 "cortetsu status (CLI)": ["cortetsu", "status"],
 "cortetsu system verify (CLI)": ["cortetsu", "system", "verify"],
}
WATCH = [H/".local/state/cortetsu", H/".config/cortetsu", H/".local/share/cortetsu/system", H/".config/hypr"]
def dgpu():
    return {d.name: (d/"power/runtime_status").read_text().strip() for d in Path("/sys/bus/pci/devices").iterdir()
            if (d/"vendor").read_text().strip() == "0x10de"}
def tree():
    s = {}
    for w in WATCH:
        for p in w.rglob("*") if w.exists() else []:
            try: s[str(p)] = p.stat().st_mtime_ns
            except OSError: pass
    return s
g0, t0 = dgpu(), tree()
res = {}
for name, cmd in CMDS.items():
    subprocess.run(cmd, capture_output=True)  # warm page cache, discarded
    xs, codes = [], set()
    for _ in range(N):
        a = time.perf_counter_ns(); r = subprocess.run(cmd, capture_output=True); xs.append((time.perf_counter_ns()-a)/1e6); codes.add(r.returncode)
    xs.sort()
    res[name] = {"n": N, "p50_ms": round(statistics.median(xs), 1), "p95_ms": round(xs[max(0, int(0.95*N)-1)], 1),
                 "min_ms": round(xs[0], 1), "max_ms": round(xs[-1], 1), "exit_codes": sorted(codes)}
g1, t1 = dgpu(), tree()
changed = sorted(k for k in set(t0) | set(t1) if t0.get(k) != t1.get(k))
meta = {"date": time.strftime("%FT%T%z"), "kernel": os.uname().release, "dgpu_before": g0, "dgpu_after": g1,
        "state_changed_during_run": changed, "governor": Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor").read_text().strip(),
        "power_profile": subprocess.run(["powerprofilesctl", "get"], capture_output=True, text=True).stdout.strip(),
        "ac_online": [p.read_text().strip() for p in Path("/sys/class/power_supply").glob("*/online")],
        "loadavg_before": open("/proc/loadavg").read().split()[:3]}
json.dump({"meta": meta, "results": res}, open(out, "w"), indent=1)
for k, v in res.items(): print(f"{k:42} p50={v['p50_ms']:8} p95={v['p95_ms']:8} rc={v['exit_codes']}")
print(json.dumps(meta, indent=1))
