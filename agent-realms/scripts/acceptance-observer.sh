#!/usr/bin/env bash
# Aceptación del observador autenticado contra un realm real:
# acceso autorizado, revocación, caída por SIGKILL, reinicio, parada del realm,
# limpieza de procesos y sockets, y foco del anfitrión intacto.
# Uso: scripts/acceptance-observer.sh [evidence-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
AR=bin/agent-realm
OUT=${1:-evidence/observer-security}
mkdir -p "$OUT"
REALM="obs-$$"
DIR="${XDG_RUNTIME_DIR:?}/cortetsu-agent-realms/observers/$REALM"
RESULT="$OUT/acceptance.txt"
: > "$RESULT"
log() { echo "$*" | tee -a "$RESULT"; }
fail() { log "FAIL: $*"; exit 1; }
cleanup() { "$AR" stop "$REALM" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Redeems a launch file like the browser page does and prints the session token.
redeem() {
  python3 - "$1" <<'PY'
import http.client, json, re, sys
text = open(sys.argv[1]).read()
port, ticket = re.search(r"127\.0\.0\.1:(\d+)/#t=([A-Za-z0-9_-]+)", text).groups()
c = http.client.HTTPConnection("127.0.0.1", int(port), timeout=5)
c.request("POST", "/api/session", json.dumps({"ticket": ticket}),
          {"Origin": f"http://127.0.0.1:{port}", "Content-Type": "application/json"})
r = c.getresponse()
print(json.loads(r.read())["token"] if r.status == 200 else f"HTTP{r.status}")
PY
}
frame_status() {  # port token -> HTTP status of /api/frame
  python3 - "$1" "$2" <<'PY'
import http.client, sys
try:
    c = http.client.HTTPConnection("127.0.0.1", int(sys.argv[1]), timeout=5)
    c.request("GET", "/api/frame", headers={"Authorization": "Bearer " + sys.argv[2]})
    r = c.getresponse(); body = r.read()
    print(r.status, "png" if body.startswith(b"\x89PNG") else "no-image")
except OSError:
    print("unreachable no-image")
PY
}
observer_pid() { "$AR" observe "$REALM" --status | jq -r '.pid // empty'; }

HOST_FOCUS=$(hyprctl activewindow -j | jq -c '{address,class}')
log "host focus before: $HOST_FOCUS"
"$AR" start --ephemeral "$REALM" | jq -e '.state == "running"' >/dev/null || fail "realm no arrancó"

launch=$("$AR" observe "$REALM" --launch-file | jq -r .launch_file)
[[ $(stat -c %a "$launch") == 600 ]] || fail "launch file no es 0600"
[[ $(stat -c %a "$DIR") == 700 ]] || fail "directorio del observador no es 0700"
port=$("$AR" observe "$REALM" --status | jq -r .port)
token=$(redeem "$launch")
[[ -e $launch ]] && fail "launch file sobrevivió al canje"
log "authorized frame: $(frame_status "$port" "$token")"
[[ $(frame_status "$port" "$token") == "200 png" ]] || fail "acceso autorizado sin imagen"
[[ $(frame_status "$port" "invalid-token") == "401 no-image" ]] || fail "token inválido aceptado"
log "invalid token: $(frame_status "$port" invalid-token)"

"$AR" observe "$REALM" --revoke >/dev/null
log "after revoke: $(frame_status "$port" "$token")"
[[ $(frame_status "$port" "$token") == "401 no-image" ]] || fail "revocación sin efecto"

token=$(redeem "$("$AR" observe "$REALM" --launch-file | jq -r .launch_file)")
pid=$(observer_pid)
kill -9 "$pid"
sleep 0.5
log "after SIGKILL: socket left=$([[ -S $DIR/control.sock ]] && echo yes || echo no), status=$("$AR" observe "$REALM" --status | jq -c .)"
"$AR" observe "$REALM" >/dev/null   # restarts over the stale socket
new_port=$("$AR" observe "$REALM" --status | jq -r .port)
log "restarted observer port $new_port; old token: $(frame_status "$new_port" "$token")"
[[ $(frame_status "$new_port" "$token") == "401 no-image" ]] || fail "token anterior válido tras reinicio"

token=$(redeem "$("$AR" observe "$REALM" --launch-file | jq -r .launch_file)")
pid=$(observer_pid)
"$AR" observe "$REALM" --stop >/dev/null
sleep 0.5
kill -0 "$pid" 2>/dev/null && fail "observer --stop dejó el proceso vivo"
"$AR" status "$REALM" | jq -e '.alive == true' >/dev/null || fail "cerrar el observador detuvo el realm"
log "observer stopped; realm still alive: yes"

"$AR" observe "$REALM" >/dev/null
pid=$(observer_pid); port=$("$AR" observe "$REALM" --status | jq -r .port)
token=$(redeem "$("$AR" observe "$REALM" --launch-file | jq -r .launch_file)")
"$AR" stop "$REALM" >/dev/null
sleep 1.5
log "after realm stop: frame=$(frame_status "$port" "$token") observer_alive=$(kill -0 "$pid" 2>/dev/null && echo yes || echo no)"
kill -0 "$pid" 2>/dev/null && fail "el observador sobrevivió a la parada del realm"
[[ -e $DIR/control.sock ]] && fail "quedó el socket de control"
leftover=$(ls "$DIR" | grep -v '^\.lock$' || true)
[[ -z $leftover ]] || fail "quedaron archivos: $leftover"
procs=$(pgrep -f "cortetsu_agent_realms.observer $REALM" || true)
[[ -z $procs ]] || fail "procesos del observador huérfanos: $procs"
scopes=$(systemctl --user list-units "agent-realm-$REALM-*" --no-legend | wc -l)
[[ $scopes == 0 ]] || fail "quedaron $scopes scopes"
log "sockets left: none; observer processes: none; scopes: 0"
[[ $(hyprctl activewindow -j | jq -c '{address,class}') == "$HOST_FOCUS" ]] || fail "cambió el foco del anfitrión"
log "host focus after: unchanged"
log "PASS"
