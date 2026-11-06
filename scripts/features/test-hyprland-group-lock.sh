#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
keybinds="$root/dotfiles/home/.config/hypr/hyprland/keybinds.lua"
grep -Fq 'create_bind(vars.kbGroupLockActive, hl.dsp.group.lock())' "$keybinds"
! grep -Fq 'hl.dsp.group.lock_active()' "$keybinds"
printf '%s\n' 'PASS: group-lock keybind keeps its configured chord and uses group.lock()'
