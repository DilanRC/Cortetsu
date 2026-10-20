#!/usr/bin/env python3
"""Shell start latency from the user journal: 'Started Cortetsu Quickshell' ->
qs 'Configuration Loaded', per start, across all retained boots (read-only)."""
import re, statistics, subprocess
boots = [l.split()[0] for l in subprocess.run(["journalctl", "--list-boots", "--no-pager", "-q"], capture_output=True, text=True).stdout.splitlines()]
xs = []
for b in boots:
    out = subprocess.run(["journalctl", "--user", "-b", b, "-u", "cortetsu-shell", "--no-pager", "-o", "short-monotonic"], capture_output=True, text=True).stdout
    start = None
    for l in out.splitlines():
        m = re.match(r"\[\s*([\d.]+)\]", l)
        if not m: continue
        t = float(m.group(1))
        if "Started Cortetsu Quickshell" in l: start = t
        elif "Configuration Loaded" in l and start is not None:
            xs.append(round((t - start) * 1000)); print(f"boot {b}: start@{start:.1f}s loaded_ms={xs[-1]}"); start = None
if xs:
    s = sorted(xs); print(f"n={len(s)} p50={statistics.median(s)} p95={s[max(0,int(0.95*len(s))-1)]} min={s[0]} max={s[-1]}")
