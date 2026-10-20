#!/bin/sh
# F0 debug tab: latest nested session logs (shell, compositor, host-command stubs).
while :; do d=$(ls -dt /tmp/czf*/ 2>/dev/null | head -1); clear; echo "== sesión: ${d:-ninguna} =="
[ -n "$d" ] && { echo "-- qs.log"; tail -n 18 "$d/logs/qs.log" 2>/dev/null | cut -c1-200; echo "-- hyprland.log (anidado)"; tail -n 8 "$d/logs/hyprland.log" 2>/dev/null | cut -c1-200; echo "-- stubs"; tail -n 5 "$d/stub-calls.log" 2>/dev/null; }; sleep 2; done
