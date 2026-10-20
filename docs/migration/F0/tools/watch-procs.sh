#!/bin/sh
# F0 debug tab: processes carrying a test XDG_RUNTIME_DIR, and the dGPU power state.
while :; do clear; date +%T; echo "dGPU: $(cat /sys/bus/pci/devices/0000:01:00.0/power/runtime_status)"; echo "procesos con XDG_RUNTIME_DIR de prueba (/tmp/czr*):"
for p in /proc/[0-9]*; do grep -qz '^XDG_RUNTIME_DIR=/tmp/czr' $p/environ 2>/dev/null && echo ${p#/proc/}; done | xargs -r ps -o pid,ppid,pcpu,rss,etime,comm -p; sleep 2; done
