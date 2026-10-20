#!/usr/bin/env bash
# Re-run the whole F0 baseline against this checkout.
# Usage: docs/migration/F0/tools/reproduce.sh [outdir]
#
# Real session: read-only probes only (status helpers, resident sampling,
# journal). Everything that opens a window runs under ws2_run.py, so nested
# compositors are born on workspace 2 without moving focus. Nothing is
# installed, reloaded or restarted.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
repo=$(cd "$here/../../../.." && pwd)
out=$(realpath -m "${1:-$repo/docs/migration/F0/evidence/run-$(date +%Y%m%d-%H%M%S)}")
ws2=("python3" "$repo/scripts/integration/ws2_run.py")
mkdir -p "$out"
cd "$repo"
# Preflight is a record, not a gate: a missing package or GPU must not abort it.
{ git status --short --branch; git rev-parse HEAD; uname -r
  pacman -Q hyprland quickshell-git qt6-base qt6-declarative kitty python rust go grim 2>&1 || true
  cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status 2>&1 || true; cat /proc/loadavg; } > "$out/preflight.txt"
"$here/real_snapshot.sh" > "$out/real-before.txt"
scripts/cortetsu status > "$out/status.txt" 2>&1 || true
scripts/cortetsu system verify > "$out/verify.txt" 2>&1 || true
systemctl --user list-units --all 'cortetsu*' --no-pager > "$out/units.txt"
python3 -I "$here/inventory.py" "$repo" > "$out/inventory.json"
python3 -I "$here/classify_tests.py" "$repo" "$out/tests-static.json"
python3 -I "$here/contract_shapes.py" "$out/contract-shapes.json"
python3 -I "$here/bench_latency.py" 30 "$out/latency.json"
python3 -I "$here/bench_resident.py" 120 3 "$out/resident.json"
python3 -I "$here/shell_startup.py" > "$out/shell-startup-journal.txt"
awk '/^test_cmd\(\)/,/^}/' scripts/cortetsu | grep -oE '"(scripts|cortetsu)/[^"]+"' | tr -d '"' > "$out/cortetsu-test-entries.txt"
"${ws2[@]}" --timeout 3600 "$out/suite.log" -- python3 -I "$here/run_suite.py" "$repo" "$out/cortetsu-test-entries.txt" "$out/suite.json" || true
"${ws2[@]}" --timeout 1800 "$out/nested.log" -- python3 "$here/nested_bench.py" "$out/nested" || true
"$here/real_snapshot.sh" > "$out/real-after.txt"
cmp -s "$out/real-before.txt" "$out/real-after.txt" && echo unchanged > "$out/real-diff.txt" || diff "$out/real-before.txt" "$out/real-after.txt" > "$out/real-diff.txt" || true
python3 -I "$here/make_baseline.py" "$out" "$out/baseline.json"
# PERF-01 (only with nobody at the keyboard): "$here/idle_measure.sh" "$out/idle" 60 4
echo "evidence in $out"
