#!/usr/bin/env bash
# Aceptación visual: Cortetsu real (Quickshell) consume los servicios simulados.
# Lanza el build de un worktree aislado dentro de un realm, abre Quick Settings y
# verifica con OCR (tesseract, español) lo que muestra la UI en cada escenario y transición.
# Uso: CORTETSU_WORKTREE=/ruta/worktree scripts/acceptance-simulation-ui.sh [evidence-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
AR=bin/agent-realm
WORKTREE=${CORTETSU_WORKTREE:-/tmp/cortetsu-agent-realms-worktree}
OUT=${1:-evidence/cortetsu-simulation}
mkdir -p "$OUT"
[[ -f $WORKTREE/dist/runtime/shell.qml ]] || { echo "falta $WORKTREE/dist/runtime/shell.qml (build de Cortetsu)"; exit 2; }
command -v tesseract >/dev/null || { echo "falta tesseract para verificar el texto de la UI"; exit 2; }
REALM="ui-$$"
SHELL_QML=/workspace/dist/runtime/shell.qml
RESULT="$OUT/ui-result.txt"
: > "$RESULT"
log() { echo "$*" | tee -a "$RESULT"; }
fail() { log "FAIL: $*"; exit 1; }
cleanup() { "$AR" stop "$REALM" >/dev/null 2>&1 || true; }
trap cleanup EXIT
ipc() { "$AR" run "$REALM" -- /usr/bin/qs ipc --path "$SHELL_QML" call "$@" 2>/dev/null | sed '/^{$/,$d'; }
launch_shell() {
  "$AR" run --detach --compositor-child "$REALM" -- /usr/bin/qs --path "$SHELL_QML" >/dev/null
  for _ in $(seq 60); do
    [[ $(ipc bottomHub isShown) =~ ^(true|false)$ ]] && return 0
    sleep 0.5
  done
  fail "Cortetsu no respondió por IPC"
}
kill_shell() { "$AR" run "$REALM" -- /usr/bin/qs kill --path "$SHELL_QML" >/dev/null 2>&1 || true; sleep 1; }
# Screenshot + OCR of the Quick Settings panel (right side), upscaled for tesseract.
ocr() {
  "$AR" screenshot "$REALM" --output "$PWD/$OUT/$1.png" >/dev/null
  python3 - "$PWD/$OUT/$1.png" "$OUT/$1.ocr.png" <<'PY'
import sys
from PIL import Image
im = Image.open(sys.argv[1])
w, h = im.size
im.crop((int(w * 0.68), int(h * 0.18), w, int(h * 0.92))).resize((int(w * 0.32) * 2, int(h * 0.74) * 2)).save(sys.argv[2])
PY
  tesseract "$OUT/$1.ocr.png" - -l spa 2>/dev/null | tr '\n' ' ' | tr -s ' '
  rm -f "$OUT/$1.ocr.png"
}
# Cortetsu exposes no IPC readout for this panel and quickSettings() toggles it,
# so the panel's own header, read by OCR, decides whether it is open.
open_quick_settings() {  # name -> prints the OCR text of the frame that shows the open panel
  local text
  for _ in $(seq 6); do
    text=$(ocr "$1")
    if grep -qi "Ajustes r" <<<"$text"; then echo "$text"; return 0; fi
    ipc bottomHub quickSettings >/dev/null
    sleep 1.5
  done
  fail "Quick Settings no se abrió"
}
expect() {  # label text pattern...
  local label=$1 text=$2; shift 2
  for pattern in "$@"; do
    grep -qiE "$pattern" <<<"$text" || fail "$label: la UI no muestra /$pattern/ (OCR: $text)"
  done
  log "$label: UI shows $*"
}

"$AR" start --lua --ephemeral --width 1600 --height 1000 --workspace "$WORKTREE" --readonly-workspace "$REALM" \
  | jq -e '.state == "running"' >/dev/null || fail "realm no arrancó"
"$AR" simulate "$REALM" --scenario battery-low >/dev/null
launch_shell
expect battery-low "$(open_quick_settings ui-battery-low)" "Bater[ií]a 12" "CortetsuLab" "Apagado" "Volumen 60"

"$AR" simulate "$REALM" --set upower.battery.percentage=50 --set 'upower.battery.state="charging"' \
  --set upower.line_power.online=true --set network.wifi.connected=null --set bluetooth.adapter.powered=true \
  --set audio.sinks.0.mute=true >/dev/null
sleep 1.5
expect transitions "$(open_quick_settings ui-transitions)" "Bater[ií]a 50" "Sin conexi[oó]n" "silenciado" "Listo"

before=$("$AR" simulate "$REALM" --status | jq .state.bluetooth.adapter.powered)
"$AR" click "$REALM" 1222 411 >/dev/null   # Bluetooth tile: Cortetsu calls busctl set-property Powered
sleep 2
after=$("$AR" simulate "$REALM" --status | jq .state.bluetooth.adapter.powered)
log "UI -> service: Bluetooth tile changed simulated Powered $before -> $after"
[[ $before == true && $after == false ]] || fail "el clic en la UI no cambió el BlueZ simulado"

kill_shell
"$AR" simulate "$REALM" --scenario services-failing >/dev/null
launch_shell
expect services-failing-at-startup "$(open_quick_settings ui-services-failing)" "Alimentaci[oó]n externa" "Sin conexi[oó]n" "Volumen 0"

"$AR" simulate "$REALM" --scenario charging >/dev/null   # PipeWire, NM and UPower come back
kill_shell
launch_shell
expect charging "$(open_quick_settings ui-charging)" "Bater[ií]a 96" "CortetsuLab" "Volumen 60"
"$AR" simulate "$REALM" --event pipewire-restart >/dev/null
"$AR" simulate "$REALM" --set network.available=false >/dev/null
sleep 1
expect live-outage "$(open_quick_settings ui-live-outage)" "Volumen 0" "Sin conexi[oó]n"
sleep 4
"$AR" simulate "$REALM" --set network.available=true >/dev/null
sleep 2
expect live-recovery-without-restart "$(open_quick_settings ui-live-recovery)" "Volumen 60" "CortetsuLab"

"$AR" stop "$REALM" >/dev/null
log "PASS"
