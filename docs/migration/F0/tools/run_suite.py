#!/usr/bin/env python3
"""Run each `cortetsu test` entry on its own and record PASS/SKIP/FAIL, time and
the real session fingerprint before/after. Run it under
scripts/integration/ws2_run.py so nested-compositor windows are born on WS 2.
Usage: python3 -I run_suite.py <repo> <tests.txt> out.json"""
import json, os, re, subprocess, sys, time
from pathlib import Path
repo, lst, out = Path(sys.argv[1]), sys.argv[2], sys.argv[3]
here = Path(__file__).parent
EXCLUDE = {"scripts/features/eval-cortetsu-process-launcher.py": "creates a transient scope in the real user systemd manager"}
snap = lambda: subprocess.run([str(here / "real_snapshot.sh")], capture_output=True, text=True).stdout
entries = [l.strip() for l in open(lst) if l.strip()]
fixtures = {"cortetsu/tests/qml/bottomhub/fixture_ScriptModelIdentity.qml": "SCRIPT_MODEL_IDENTITY_PASS", "cortetsu/StartupPageFixture.qml": "STARTUP_PAGE_PASS"}
rows = []
base = snap()
for e in entries:
    if e in EXCLUDE:
        rows.append({"test": e, "result": "NOT_RUN", "reason": EXCLUDE[e]}); continue
    # A directory is a Qt Quick Test suite, as in `run_qml_test` of scripts/cortetsu.
    if (repo / e).is_dir(): cmd, env = ["/usr/lib/qt6/bin/qmltestrunner", "-input", str(repo / e)], {"QT_QPA_PLATFORM": "offscreen"}
    elif e in fixtures: cmd, env = ["qs", "-p", str(repo / e), "--no-color"], {}
    elif e.endswith(".js"): cmd, env = ["node", str(repo / e)], {}
    elif e.endswith(".sh"): cmd, env = ["bash", str(repo / e)], {}
    else: cmd, env = ["python3", str(repo / e)], {}
    t = time.monotonic()
    try:
        r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True, timeout=600, env={**os.environ, **env})
        o, rc = r.stdout + r.stderr, r.returncode
    except subprocess.TimeoutExpired as x:
        o, rc = str(x), "timeout"
    dt = round(time.monotonic() - t, 2)
    skip = [l for l in o.splitlines() if re.search(r"\bSKIP\b", l)]
    if rc != 0: res = "FAIL"
    elif e in fixtures and fixtures[e] not in o: res = "FAIL"
    elif skip and not re.search(r"\bPASS\b|passed|Totals: \d+ passed", o): res = "SKIP"
    elif skip: res = "PASS_WITH_SKIPS"
    else: res = "PASS"
    now = snap()
    rows.append({"test": e, "result": res, "rc": rc, "seconds": dt, "skip_lines": skip[:5],
                 "tail": o.strip().splitlines()[-3:] if res == "FAIL" else o.strip().splitlines()[-1:],
                 "real_session_changed": now != base})
    print(f"{res:16} {dt:7}s {e}", flush=True)
    base = now
json.dump(rows, open(out, "w"), indent=1)
