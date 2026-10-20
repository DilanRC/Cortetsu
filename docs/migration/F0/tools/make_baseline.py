#!/usr/bin/env python3
"""Merge one evidence directory into baseline.json, the comparison point for F1+.

Usage: python3 -I make_baseline.py EVIDENCE_DIR OUT.json
Reads what reproduce.sh writes there: preflight.txt, latency.json,
resident.json, suite.json, shell-startup-journal.txt and nested/nested-bench.json.
Real-session and nested numbers stay in separate keys: they are not comparable.
"""
import json
import statistics
import sys
from pathlib import Path

E, out = Path(sys.argv[1]), Path(sys.argv[2])
load = lambda name: json.loads((E / name).read_text()) if (E / name).exists() else None

lat, res, suite, nested = load("latency.json"), load("resident.json"), load("suite.json"), load("nested/nested-bench.json")
baseline = {"preflight": (E / "preflight.txt").read_text().splitlines()[:12]}

if lat:
    baseline["real_session"] = {"conditions": lat["meta"], "helper_latency_ms": lat["results"]}
if res:
    units = {}
    for unit in res["runs"][0]["units"]:
        rows = [run["units"][unit] for run in res["runs"]]
        cpu = sorted(r["cpu_pct_one_core"] for r in rows)
        pss = sorted(sum(p.get("pss_mib", 0) for p in r["procs"].values()) for r in rows)
        units[unit] = {"windows": len(rows), "window_s": res["window_s"],
                       "cpu_pct_one_core_median": statistics.median(cpu), "cpu_pct_min_max": [cpu[0], cpu[-1]],
                       "pss_sum_mib_median": round(statistics.median(pss), 1),
                       "transient_pids": [r["transient_pids"] for r in rows]}
    baseline.setdefault("real_session", {})["resident"] = units
if (E / "shell-startup-journal.txt").exists():
    lines = (E / "shell-startup-journal.txt").read_text().strip().splitlines()
    baseline.setdefault("real_session", {})["shell_start_journal"] = lines[-1] if lines else None
if suite:
    by = {}
    for row in suite:
        by[row["result"]] = by.get(row["result"], 0) + 1
    baseline["suite"] = {"entries": len(suite), "by_result": by,
                         "fail": [r["test"] for r in suite if r["result"] == "FAIL"],
                         "skip": [r["test"] for r in suite if r["result"] in ("SKIP", "PASS_WITH_SKIPS")],
                         "not_run": [r["test"] for r in suite if r["result"] == "NOT_RUN"],
                         "real_session_changed": [r["test"] for r in suite if r.get("real_session_changed")],
                         "seconds": round(sum(r.get("seconds", 0) for r in suite), 1)}
if nested:
    baseline["nested"] = {k: nested[k] for k in ("head", "dirty", "monitors", "shell_start_configuration_loaded", "shell_start_ready", "surfaces",
                                                 "ipc_roundtrip", "grim_capture", "gamemode", "cleanup")}
    samples = nested["soak"]["samples"]
    baseline["nested"]["soak"] = {"cycles": nested["soak"]["cycles"], "first": samples[0], "last": samples[-1],
                                  "pss_growth_mib": round(samples[-1]["pss_mib"] - samples[0]["pss_mib"], 1),
                                  "state_failures": nested["soak"]["state_failures"],
                                  "new_qml_warnings": nested["soak"]["new_qml_warnings"],
                                  "new_qml_warning_classes": nested["soak"].get("new_qml_warning_classes")}
out.write_text(json.dumps(baseline, indent=1, ensure_ascii=False))
print(json.dumps({k: list(v) if isinstance(v, dict) else v for k, v in baseline.items() if k != "preflight"}, indent=1))
