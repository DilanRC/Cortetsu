#!/usr/bin/env python3
"""Golden *shapes* of read-only helper replies (keys and types, never values,
so nothing personal is stored) plus exit code/stderr of invalid input.
Usage: python3 -I contract_shapes.py out.json"""
import json, subprocess, sys
def shape(v, depth=0):
    if isinstance(v, dict): return {k: shape(x, depth + 1) for k, x in sorted(v.items())} if depth < 3 else "object"
    if isinstance(v, list): return [shape(v[0], depth + 1)] if v else []
    return type(v).__name__
CASES = {
 "gamemode status": ["cortetsu-gamemode", "status"],
 "gamemode invalid action": ["cortetsu-gamemode", "bogus"],
 "keybinds list": ["cortetsu-keybinds", "list"],
 "keybinds invalid": ["cortetsu-keybinds", "bogus"],
 "record status": ["cortetsu-record", "status"],
 "record invalid": ["cortetsu-record", "bogus"],
 "display-probe": ["cortetsu-display-probe"],
 "display-transaction status": ["cortetsu-display-transaction", "status"],
 "power-auto-control status": ["cortetsu-power-auto-control", "status"],
 "power-auto-control invalid": ["cortetsu-power-auto-control", "bogus"],
 "hardware-probe": ["cortetsu-hardware-probe"],
 "scheme list": ["cortetsu-scheme", "list"],
 "cortetsu doctor --json": ["cortetsu", "doctor", "--json"],
}
res = {}
for k, c in CASES.items():
    r = subprocess.run(c, capture_output=True, text=True, timeout=30)
    try: body = shape(json.loads(r.stdout))
    except ValueError: body = {"non_json_lines": len(r.stdout.splitlines())}
    res[k] = {"argv": c, "rc": r.returncode, "stdout_shape": body, "stderr_first": r.stderr.strip().splitlines()[:1]}
    print(f"{k:32} rc={r.returncode} {str(body)[:110]} {res[k]['stderr_first']}")
json.dump(res, open(sys.argv[1], "w"), indent=1, ensure_ascii=False)
