#!/usr/bin/env bash
# Supervised test: does the HDMI output (NVIDIA, card1) come back after s2idle?
#
#   hdmi-s2idle-supervised.sh preflight            read only
#   hdmi-s2idle-supervised.sh run --authorized     suspends once; Dilan wakes it
#   hdmi-s2idle-supervised.sh recover              DPMS off/on of the HDMI only
#
# The question is not "is the screen black" but which of these happened:
#   OK                 image, lock screen, pointer moves, capture works
#   ASLEEP             the monitor reports no signal / standby AND the PC side
#                      has the output off (DPMS Off); input wakes it
#   FROZEN             the monitor shows an image that does not change while
#                      the PC side says the output is on, or the capture of
#                      HDMI-A-1 hangs
#   LINK_LOST          the monitor reports no signal while the PC side says
#                      the output is on and enabled
# The PC-side readings are taken by the script; the monitor-side ones are
# Dilan's answers, recorded verbatim. Nothing here restarts Quickshell or
# Hyprland or changes kernel, firmware or NVIDIA settings.
set -euo pipefail

MONITOR=HDMI-A-1
CONNECTOR=/sys/class/drm/card1-HDMI-A-1
DGPU=/sys/bus/pci/devices/0000:01:00.0
STAMP=$(date +%Y%m%d-%H%M%S)
OUT="${CORTETSU_QA_DIR:-$HOME/.local/state/cortetsu/qa}/hdmi-s2idle-$STAMP"
HYPRLOG="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE:?run inside the Hyprland session}/hyprland.log"

say() { printf '%s\n' "$*" | tee -a "$OUT/run.log"; }

# One timestamped reading of every PC-side signal.
snapshot() {
    local tag=$1 dir="$OUT/$1"
    mkdir -p "$dir"
    date --iso-8601=ns > "$dir/time"
    hyprctl monitors -j > "$dir/monitors.json" 2>&1 || true
    for f in status enabled dpms; do printf '%s=%s\n' "$f" "$(cat "$CONNECTOR/$f" 2>&1)"; done > "$dir/connector"
    cat "$DGPU/power/runtime_status" > "$dir/dgpu" 2>&1 || true
    cat /sys/power/suspend_stats/success /sys/power/suspend_stats/fail > "$dir/suspend_stats" 2>&1 || true
    cat /sys/power/pm_wakeup_irq > "$dir/wakeup_irq" 2>&1 || true
    cat /proc/acpi/wakeup > "$dir/acpi_wakeup" 2>&1 || true
    cat /sys/class/power_supply/AC*/online /sys/class/power_supply/BAT0/capacity > "$dir/power" 2>&1 || true
    # A frozen output hung grim on 2026-10-20; the timeout is the measurement.
    if timeout 6 grim -o "$MONITOR" "$dir/hdmi.png" 2> "$dir/grim.err"; then echo ok > "$dir/grim"; else echo "fail $?" > "$dir/grim"; fi
}

hypr_dpms() {
    hyprctl monitors -j | python3 -c 'import json,sys; m=[m for m in json.load(sys.stdin) if m["name"]==sys.argv[1]]; print(("on" if m[0]["dpmsStatus"] else "off") if m else "absent")' "$MONITOR"
}

ask() {
    local answer
    read -r -p "$1 [s/n] " answer
    printf '%s => %s\n' "$1" "$answer" >> "$OUT/answers"
    [[ $answer == [sS]* ]]
}

preflight() {
    mkdir -p "$OUT"
    local bad=0
    [[ $(cat "$CONNECTOR/status") == connected ]] || { say "FAIL: $MONITOR no está conectado"; bad=1; }
    [[ $(cat "$CONNECTOR/dpms") == On && $(hypr_dpms) == on ]] || { say "FAIL: $MONITOR no está encendido (DPMS)"; bad=1; }
    grep -q '\[s2idle\]' /sys/power/mem_sleep || { say "FAIL: mem_sleep no es s2idle"; bad=1; }
    [[ $(cat /sys/class/power_supply/AC*/online 2>/dev/null | head -1) == 1 ]] || { say "FAIL: sin corriente alterna"; bad=1; }
    if command -v cortetsu-gamemode >/dev/null && cortetsu-gamemode status 2>/dev/null | grep -q '^ACTIVE'; then
        say "FAIL: modo juego activo"; bad=1
    fi
    snapshot pre
    [[ $(cat "$OUT/pre/grim") == ok ]] || { say "FAIL: la captura de $MONITOR ya falla antes de suspender"; bad=1; }
    say "preflight: $([[ $bad == 0 ]] && echo PASS || echo FAIL) · evidencia en $OUT"
    return $bad
}

recover() {
    mkdir -p "$OUT"
    say "recuperación: DPMS off/on solo en $MONITOR"
    hyprctl dispatch "hl.dsp.dpms({ action = \"off\", monitor = \"$MONITOR\" })" | tee -a "$OUT/run.log"
    sleep 2
    hyprctl dispatch "hl.dsp.dpms({ action = \"on\", monitor = \"$MONITOR\" })" | tee -a "$OUT/run.log"
    sleep 3
    snapshot recovered
    say "tras recuperar: hyprland=$(hypr_dpms) $(tr '\n' ' ' < "$OUT/recovered/connector") captura=$(cat "$OUT/recovered/grim")"
    say "Si sigue sin imagen: desconecta y reconecta el cable HDMI; eDP-1 sigue disponible en todo momento."
}

run() {
    [[ ${1:-} == --authorized ]] || { echo "run exige --authorized (autorización explícita de Dilan para esta suspensión)"; exit 2; }
    preflight || { echo "preflight FAIL: no se suspende"; exit 1; }
    local logstart; logstart=$(stat -c %s "$HYPRLOG")
    local since; since=$(date '+%Y-%m-%d %H:%M:%S')
    say "Se suspenderá UNA vez con systemctl suspend. Cortetsu bloquea antes de dormir."
    say "Para despertar: botón de encendido o una tecla del portátil. No toques el cable HDMI."
    local confirm; read -r -p "Escribe SUSPENDER para continuar: " confirm
    [[ $confirm == SUSPENDER ]] || { say "cancelado"; exit 1; }
    date --iso-8601=ns > "$OUT/suspend-requested"
    systemctl suspend
    # systemctl returns at once; wait for the resume to be visible to userspace.
    local before; before=$(cat "$OUT/pre/suspend_stats" | head -1)
    for _ in $(seq 1 600); do
        [[ $(cat /sys/power/suspend_stats/success) != "$before" || $(cat /sys/power/suspend_stats/fail) != "$(sed -n 2p "$OUT/pre/suspend_stats")" ]] && break
        sleep 1
    done
    sleep 8  # let the outputs come back before measuring
    snapshot post
    tail -c +"$((logstart + 1))" "$HYPRLOG" > "$OUT/hyprland.log" || true
    journalctl -k --since "$since" --no-pager > "$OUT/kernel.log" 2>&1 || true
    journalctl --user --since "$since" --no-pager -u cortetsu-shell > "$OUT/shell.log" 2>&1 || true
    grep -ciE 'EINVAL|failed to commit|auto-value-update' "$OUT/hyprland.log" > "$OUT/commit-errors" || true

    local pc_dpms; pc_dpms=$(hypr_dpms)
    local kdpms; kdpms=$(cat "$CONNECTOR/dpms")
    local grimres; grimres=$(cat "$OUT/post/grim")
    say "PC: hyprland=$pc_dpms conector=$kdpms captura=$grimres errores_commit=$(cat "$OUT/commit-errors") dGPU=$(cat "$OUT/post/dgpu")"

    local verdict
    if ask "¿El monitor externo muestra imagen (no 'sin señal' ni LED de reposo)?"; then
        if ask "¿Muestra la pantalla de bloqueo de Cortetsu?" && ask "¿El puntero se mueve sobre él al mover el ratón?"; then
            verdict=OK
        else
            verdict=FROZEN
        fi
    elif [[ $pc_dpms == off || $kdpms == Off ]]; then
        if ask "Mueve el ratón o pulsa una tecla. ¿Vuelve la imagen?"; then verdict=ASLEEP; else verdict=ASLEEP_NO_WAKE; fi
    else
        verdict=LINK_LOST
    fi
    [[ $verdict == OK && $grimres != ok ]] && verdict=FROZEN_CAPTURE
    say "VEREDICTO: $verdict"
    echo "$verdict" > "$OUT/verdict"
    if [[ $verdict != OK && $verdict != ASLEEP ]] && ask "¿Intento la recuperación (DPMS off/on del HDMI)?"; then
        recover
        ask "¿Volvió la imagen correcta al monitor externo?" && say "recuperado con DPMS" || say "no recuperado con DPMS"
    fi
    say "Evidencia: $OUT"
}

case ${1:-} in
    preflight) preflight ;;
    run) shift; run "$@" ;;
    recover) recover ;;
    *) sed -n '2,8p' "$0"; exit 2 ;;
esac
