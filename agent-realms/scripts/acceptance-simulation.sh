#!/usr/bin/env bash
# Aceptación de los servicios simulados contra un realm real.
# Comprueba servicios en el bus privado, transiciones con señales D-Bus reales,
# PipeWire privado sin dispositivos físicos, y que nada del anfitrión cambia.
# La verificación visual con Cortetsu real está en scripts/acceptance-simulation-ui.sh.
# Uso: scripts/acceptance-simulation.sh [evidence-dir]
set -euo pipefail
cd "$(dirname "$0")/.."
AR=bin/agent-realm
OUT=${1:-evidence/simulation-acceptance}
mkdir -p "$OUT"
REALM="sim-$$"
RESULT="$OUT/result.txt"
: > "$RESULT"
log() { echo "$*" | tee -a "$RESULT"; }
fail() { log "FAIL: $*"; exit 1; }
cleanup() { "$AR" stop "$REALM" >/dev/null 2>&1 || true; }
trap cleanup EXIT
inrealm() { "$AR" run "$REALM" -- /bin/sh -c "$1; echo" 2>/dev/null | sed "/^{$/,\$d" | sed "/^$/d"; }
digest() { sha256sum | cut -c1-12; }

# Host fingerprint: hashes only, so no SSID or device name lands in evidence.
host_state() {
  {
    hyprctl activewindow -j | jq -c '{address,class}'
    busctl --system get-property org.freedesktop.UPower.PowerProfiles /org/freedesktop/UPower/PowerProfiles \
      org.freedesktop.UPower.PowerProfiles ActiveProfile 2>/dev/null || echo no-ppd
    wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || echo no-wpctl
    nmcli -t -f WIFI,STATE general 2>/dev/null || echo no-nm
    nmcli -t -f NAME,DEVICE connection show --active 2>/dev/null | sort || true
    busctl --system get-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered 2>/dev/null || echo no-bt
  } | digest
}
HOST_BEFORE=$(host_state)
log "host fingerprint before: $HOST_BEFORE"

"$AR" start --ephemeral "$REALM" | jq -e '.state == "running"' >/dev/null || fail "realm no arrancó"
t0=$(date +%s%N)
"$AR" simulate "$REALM" --scenario battery-low > "$OUT/start.json"
log "simulation start: $(( ($(date +%s%N) - t0) / 1000000 )) ms; errors=$(jq -c .errors "$OUT/start.json")"
jq -e '.started and .audio_live.running' "$OUT/start.json" >/dev/null || fail "la simulación no arrancó completa"

names=$(inrealm 'busctl --system list --no-pager | awk "{print \$1}" | grep -v "^:" | grep -v NAME | sort | tr "\n" " "')
log "realm system bus: $names"
for name in org.freedesktop.UPower org.freedesktop.UPower.PowerProfiles org.freedesktop.NetworkManager org.bluez; do
  [[ " $names " == *" $name "* ]] || fail "falta $name en el bus privado"
done
[[ $(inrealm 'test -e /run/dbus/system_bus_socket && echo host-bus || echo isolated') == isolated ]] \
  || fail "el realm ve el bus de sistema del anfitrión"
[[ $(inrealm 'ls /dev/snd 2>/dev/null | wc -l') == 0 ]] || fail "el realm ve dispositivos de audio físicos"
log "host system bus and /dev/snd: not visible inside the realm"

pct=$(inrealm 'busctl --system get-property org.freedesktop.UPower /org/freedesktop/UPower/devices/DisplayDevice org.freedesktop.UPower.Device Percentage')
[[ $pct == "d 12" ]] || fail "UPower no informa 12 %: $pct"

"$AR" run --detach "$REALM" -- /bin/sh -c 'exec dbus-monitor --system > /home/agent/monitor.log 2>&1' >/dev/null
sleep 0.8
"$AR" simulate "$REALM" --set upower.battery.percentage=50 >/dev/null
"$AR" simulate "$REALM" --set upower.battery.percentage=12 >/dev/null
"$AR" simulate "$REALM" --set network.wifi.connected=null >/dev/null
"$AR" simulate "$REALM" --set bluetooth.adapter.powered=true >/dev/null
"$AR" simulate "$REALM" --set 'audio.sinks.0.mute=true' >/dev/null
"$AR" simulate "$REALM" --set 'power_profiles.active="performance"' >/dev/null
"$AR" simulate "$REALM" --event wifi-scan >/dev/null
"$AR" simulate "$REALM" --event bt-discover >/dev/null
sleep 1
monitor="${XDG_DATA_HOME:-$HOME/.local/share}/cortetsu-agent-realms/$REALM/home/monitor.log"
count() { grep -c "$1" "$monitor" || true; }
log "signals: UPower PropertiesChanged=$(grep -A0 'path=/org/freedesktop/UPower/devices/DisplayDevice; interface=org.freedesktop.DBus.Properties; member=PropertiesChanged' "$monitor" | wc -l)" \
    "NM Device.StateChanged=$(count 'member=StateChanged')" "AccessPointAdded=$(count 'member=AccessPointAdded')" \
    "InterfacesAdded=$(count 'member=InterfacesAdded')"
for member in 'interface=org.freedesktop.NetworkManager.Device; member=StateChanged' 'member=AccessPointAdded' \
              'member=InterfacesAdded' 'path=/org/freedesktop/UPower/PowerProfiles; interface=org.freedesktop.DBus.Properties'; do
  grep -q "$member" "$monitor" || fail "no se emitió $member"
done
[[ $(grep -c 'path=/org/freedesktop/UPower/devices/DisplayDevice; interface=org.freedesktop.DBus.Properties; member=PropertiesChanged' "$monitor") -ge 2 ]] \
  || fail "UPower no emitió dos PropertiesChanged para 50 % -> 12 %"

state=$("$AR" simulate "$REALM" --status)
jq -e '.audio_live.nodes.sim_speakers.mute == true' <<<"$state" >/dev/null || fail "mute no llegó al nodo PipeWire"
"$AR" simulate "$REALM" --set audio.playback=true >/dev/null
sleep 1
streams=$("$AR" simulate "$REALM" --status | jq -r '[.audio_live.nodes[] | select(.application != null) | .application] | join(",")')
log "realm audio streams: $streams"
[[ $streams == *"Reproductor simulado"* ]] || fail "no apareció el stream simulado"
if command -v pw-dump >/dev/null && pw-dump 2>/dev/null | grep -q "Reproductor simulado"; then
  fail "el stream simulado llegó al PipeWire del anfitrión"
fi
log "host PipeWire: no simulated stream"

"$AR" simulate "$REALM" --scenario services-failing >/dev/null
gone=$(inrealm 'busctl --system list --no-pager | grep -c -E "org.freedesktop.(UPower |NetworkManager)" || true')
[[ $gone == 0 ]] || fail "UPower o NetworkManager siguen en el bus en services-failing"
err=$(inrealm 'busctl --system set-property org.bluez /org/bluez/hci0 org.bluez.Adapter1 Powered b false 2>&1 || true')
[[ -n $err ]] || fail "BlueZ aceptó una operación en modo error"
"$AR" simulate "$REALM" --status | jq -e '.audio_live.running == false' >/dev/null || fail "PipeWire no está reiniciándose"
sleep 3.5
"$AR" simulate "$REALM" --status | jq -e '.audio_live.running == true' >/dev/null || fail "PipeWire no volvió tras el reinicio"
log "services-failing: UPower and NM gone, BlueZ errors, PipeWire restarted and recovered"


"$AR" simulate "$REALM" --stop >/dev/null
[[ $(inrealm 'ls $XDG_RUNTIME_DIR | grep -c -E "system_bus_socket|pipewire-0" || true') == 0 ]] \
  || fail "quedaron sockets de la simulación"
"$AR" stop "$REALM" >/dev/null
scopes=$(systemctl --user list-units "agent-realm-$REALM-*" --no-legend | wc -l)
[[ $scopes == 0 ]] || fail "quedaron $scopes scopes"
log "simulation sockets: removed; scopes left: 0"

HOST_AFTER=$(host_state)
log "host fingerprint after: $HOST_AFTER"
[[ $HOST_AFTER == "$HOST_BEFORE" ]] || fail "cambió el estado del anfitrión (perfil, audio, red, Bluetooth o foco)"
log "PASS"
