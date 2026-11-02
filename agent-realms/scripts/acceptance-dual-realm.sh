#!/usr/bin/env bash
# Aceptación: dos realms (codex, claude) reciben entrada en paralelo sin
# compartir foco ni entrada entre ellos ni con el anfitrión.
# Uso: scripts/acceptance-dual-realm.sh [evidence-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
AR=bin/agent-realm
OUT=${1:-evidence/acceptance-dual-realm}
mkdir -p "$OUT"
SUFFIX=$$
REALMS=("codex-$SUFFIX" "claude-$SUFFIX")
fail() { echo "FAIL: $*" | tee -a "$OUT/result.txt"; exit 1; }
cleanup() { for r in "${REALMS[@]}"; do "$AR" stop "$r" >/dev/null 2>&1 || true; done; }
trap cleanup EXIT

host_state() { hyprctl activewindow -j | jq -c '{address,class}'; }
host_cursor() { hyprctl cursorpos; }
host_latency_ms() {  # mediana de 15 llamadas IPC al Hyprland del anfitrión
  for _ in $(seq 15); do
    s=$(date +%s%N); hyprctl -j version >/dev/null; e=$(date +%s%N); echo $(((e - s) / 1000))
  done | sort -n | awk '{a[NR]=$1} END {printf "%.2f", a[int((NR+1)/2)]/1000}'
}

: > "$OUT/result.txt"
echo "host focus before: $(host_state)  cursor: $(host_cursor)" | tee -a "$OUT/result.txt"
echo "host IPC latency idle (ms): $(host_latency_ms)" | tee -a "$OUT/result.txt"
HOST_FOCUS=$(host_state); HOST_CURSOR=$(host_cursor)

for r in "${REALMS[@]}"; do
  "$AR" start --ephemeral "$r" > "$OUT/$r-start.json" &
done
wait
for r in "${REALMS[@]}"; do
  [[ $(jq -r .state "$OUT/$r-start.json") == running ]] || fail "$r no arrancó"
  "$AR" run --detach --compositor-child "$r" -- kitty --title "idle-$r" >/dev/null
done
sleep 3

# Entrada simultánea: cada realm escribe un marcador en su propio HOME privado.
for r in "${REALMS[@]}"; do
  (
    "$AR" click "$r" 640 400 >/dev/null
    "$AR" type "$r" "echo MARK-$r >> ~/mark" >/dev/null
    "$AR" key "$r" Return >/dev/null
  ) &
done
LAT_BUSY=$(host_latency_ms)
wait
sleep 1
echo "host IPC latency while realms receive input (ms): $LAT_BUSY" | tee -a "$OUT/result.txt"

for r in "${REALMS[@]}"; do
  "$AR" windows "$r" > "$OUT/$r-windows.json"
  "$AR" screenshot --output "$OUT/$r.png" "$r" >/dev/null
  "$AR" inspect "$r" > "$OUT/$r-inspect.json"
  titles=$(jq -c '[.[].title]' "$OUT/$r-windows.json")
  echo "$r windows: $titles" | tee -a "$OUT/result.txt"
  mark="${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu-agent-realms/$r/home/mark"
  echo "$r mark: $(cat "$mark" 2>/dev/null | tr '\n' ' ')" | tee -a "$OUT/result.txt"
  [[ $(cat "$mark" 2>/dev/null) == "MARK-$r" ]] || fail "$r no recibió exactamente su propia entrada"
  jq -c --arg r "$r" '{realm:$r, processes:.resources.process_count, pss_kib:.resources.pss_kib,
       cpu_seconds:.resources.cpu_seconds, amd_gpu_busy_percent_global:.resources.amd_gpu_busy_percent_global}' \
    "$OUT/$r-inspect.json" 2>/dev/null | tee -a "$OUT/result.txt" || true
done

echo "host focus after: $(host_state)  cursor: $(host_cursor)" | tee -a "$OUT/result.txt"
[[ $(host_state) == "$HOST_FOCUS" ]] || fail "cambió el foco del anfitrión"
[[ $(host_cursor) == "$HOST_CURSOR" ]] || echo "NOTE: el cursor del anfitrión se movió (¿lo movió el usuario?)" | tee -a "$OUT/result.txt"
for r in "${REALMS[@]}"; do "$AR" stop "$r" >/dev/null; done
left=$(systemctl --user list-units "agent-realm-*-$SUFFIX-*" --no-legend | wc -l)
[[ $left == 0 ]] || fail "quedaron $left scopes"
echo "scopes left: 0" | tee -a "$OUT/result.txt"
echo "PASS" | tee -a "$OUT/result.txt"
