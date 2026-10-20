#!/usr/bin/env bash
# PERF-01: resident cost while nobody touches the machine. Input IRQ counts
# (keyboard i8042, i2c-hid touchpad, xhci USB) before/after prove idleness.
# Usage: idle_measure.sh outdir [delay_s] [windows]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd); out=$1; delay=${2:-60}; n=${3:-4}
mkdir -p "$out"
irq() { grep -iE "i8042|hid|xhci|elan" /proc/interrupts | awk '{s=0; for(i=2;i<=NF;i++) if($i ~ /^[0-9]+$/) s+=$i; print $1, s, $NF}'; }
sleep "$delay"
irq > "$out/irq-before.txt"; date +%FT%T%z > "$out/start.txt"
python3 -I "$here/bench_resident.py" 120 "$n" "$out/resident-idle.json" > "$out/resident-idle.log"
irq > "$out/irq-after.txt"; date +%FT%T%z > "$out/end.txt"
paste "$out/irq-before.txt" "$out/irq-after.txt" | awk '{print $1, $6, $5-$2, "input IRQs during window"}' > "$out/irq-delta.txt"
