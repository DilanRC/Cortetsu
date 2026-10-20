#!/usr/bin/env python3
"""Static classification of every test/eval file: which gate runs it, whether it
nests Hyprland/Quickshell, can SKIP, reads hardware, or could reach the real
session. Usage: python3 -I classify_tests.py <repo> out.json"""
import json, re, subprocess, sys
from pathlib import Path
repo = Path(sys.argv[1]); out = sys.argv[2]
ls = subprocess.run(["git", "-C", repo, "ls-files"], capture_output=True, text=True).stdout.split()
tests = [f for f in ls if re.search(r"(^|/)(test|eval|tst)[-_][^/]*\.(py|sh|js|qml)$", f) and not f.startswith("docs/")]
cli = (repo / "scripts/cortetsu").read_text(); build = (repo / "cortetsu/bin/build-runtime.sh").read_text()
install = (repo / "scripts/install-cortetsu.sh").read_text()
ci = "".join(p.read_text() for p in (repo / ".github/workflows").glob("*.yml")) if (repo / ".github/workflows").exists() else ""
def gates(f):
    d = Path(f).parent.as_posix()
    g = []
    if f in cli or (f.endswith(".qml") and d in cli): g.append("cortetsu-test")
    if f in build or Path(f).name in build or (f.endswith(".qml") and d in build): g.append("build-runtime(install)")
    if f in install: g.append("install-script")
    if f in ci or Path(f).name in ci: g.append("ci")
    return g
R = {
 "nested_hyprland": r'\[\s*"Hyprland"|Popen\(\["Hyprland"|nested_hypr|compositor_env',
 "quickshell_process": r'\["qs"|"qs",|\bqs -p\b',
 "skip_path": r'SKIP',
 "needs_wayland": r'WAYLAND_DISPLAY',
 "hardware_sysfs": r'/sys/class/(power_supply|backlight|drm|input|leds)|/sys/bus/pci|/dev/input|evdev|nvidia-smi|/proc/acpi',
 "real_session_risk": r'ydotool|hyprctl"?,?\s*"?(dispatch|reload|keyword)|systemctl", "--user", "(restart|stop|start)|qs ipc call(?! --pid)|os\.environ\["HYPRLAND_INSTANCE_SIGNATURE"\]',
 "temp_home": r'TemporaryDirectory|mkdtemp|mktemp|"HOME":|HOME=',
 "network": r'urllib\.request|requests\.|curl |http[s]?://(?!www\.w3)',
 "git_history": r'git", "(show|log|rev-parse|cat-file)|6e3fdaf',
}
rows = []
for f in tests:
    t = (repo / f).read_text(errors="replace")
    row = {"path": f, "gates": gates(f)}
    for k, rx in R.items(): row[k] = bool(re.search(rx, t))
    rows.append(row)
json.dump(rows, open(out, "w"), indent=1)
import collections
c = collections.Counter()
for r in rows:
    c["total"] += 1
    c["in_any_gate" if r["gates"] else "orphan(no gate)"] += 1
    for k in R:
        if r[k]: c[k] += 1
print(dict(c))
