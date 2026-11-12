#!/usr/bin/env bash
# The greeter compositor launcher names the internal panel's card, starts
# weston again when it dies at once, and leaves a working greeter alone.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LAUNCHER="$ROOT/config/sddm/cortetsu-greeter-compositor"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# Card numbers move between boots: here the discrete card comes first.
drm="$WORK/drm"
mkdir -p "$drm/card1/device" "$drm/card1-HDMI-A-1" "$drm/card2/device" "$drm/card2-eDP-1" "$drm/card2-DP-1"
echo 0 > "$drm/card1/device/boot_vga"
echo 1 > "$drm/card2/device/boot_vga"

# A weston that logs its arguments and follows a script of exit codes.
cat > "$WORK/weston" <<'FAKE'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
n=$(wc -l < "$FAKE_LOG")
code=$(sed -n "${n}p" "$FAKE_PLAN")
case "${code:-0}" in
    hang) trap 'echo terminated >> "$FAKE_LOG"; exit 0' TERM; sleep 30 & wait ;;
    *) exit "${code:-0}" ;;
esac
FAKE
chmod +x "$WORK/weston"
run() {
    : > "$WORK/log"
    printf '%s\n' "$@" > "$WORK/plan"
    CORTETSU_GREETER_DRM="$drm" CORTETSU_GREETER_WESTON="$WORK/weston" FAKE_LOG="$WORK/log" FAKE_PLAN="$WORK/plan" \
        "$LAUNCHER" --shell=kiosk --config=/etc/sddm/weston.ini 2> "$WORK/stderr"
}

run 1 1 0 || fail "a greeter that comes up on the third try is a success"
[[ "$(wc -l < "$WORK/log")" == 3 ]] || fail "expected three starts: $(cat "$WORK/log")"
[[ "$(sort -u "$WORK/log")" == "--drm-device=card2 --shell=kiosk --config=/etc/sddm/weston.ini" ]] \
    || fail "every start names the eDP card and keeps the arguments: $(cat "$WORK/log")"
grep -q "attempt 2 of 6" "$WORK/stderr" || fail "each early exit is reported"

status=0; run 1 1 1 1 1 1 1 || status=$?
[[ "$status" == 1 && "$(wc -l < "$WORK/log")" == 6 ]] || fail "gives up after six starts with weston's status ($status)"

# No eDP connector (a desktop, or the panel's driver missing): the boot display.
rm -r "$drm/card2-eDP-1"
run 0
[[ "$(cat "$WORK/log")" == "--drm-device=card2 "* ]] || fail "falls back to boot_vga: $(cat "$WORK/log")"
# Nothing to go by: weston chooses, as before.
echo 0 > "$drm/card2/device/boot_vga"
run 0
[[ "$(cat "$WORK/log")" == "--shell=kiosk "* ]] || fail "no card is named when none qualifies: $(cat "$WORK/log")"

# SDDM stops the greeter with SIGTERM at login: weston gets it, no restart.
: > "$WORK/log"; echo hang > "$WORK/plan"
CORTETSU_GREETER_DRM="$drm" CORTETSU_GREETER_WESTON="$WORK/weston" FAKE_LOG="$WORK/log" FAKE_PLAN="$WORK/plan" \
    "$LAUNCHER" 2>/dev/null &
pid=$!
for _ in $(seq 50); do [[ -s "$WORK/log" ]] && break; sleep 0.1; done
kill -TERM "$pid"
wait "$pid" || true
grep -q terminated "$WORK/log" || fail "SIGTERM reaches weston"
[[ "$(grep -vc terminated "$WORK/log")" == 1 ]] || fail "a stopped greeter is not started again"

# The installer rewrites only the CompositorCommand line and can undo it.
sys="$WORK/sys"; mkdir -p "$sys/etc"
printf '[General]\nDisplayServer=wayland\n\n[Wayland]\nCompositorCommand=weston --shell=kiosk --config=/etc/sddm/weston.ini\n' > "$sys/etc/sddm.conf"
cp "$sys/etc/sddm.conf" "$WORK/original.conf"
CORTETSU_SYSTEM_ROOT="$sys" bash "$ROOT/scripts/install-sddm-greeter.sh" > /dev/null
CORTETSU_SYSTEM_ROOT="$sys" bash "$ROOT/scripts/install-sddm-greeter.sh" > /dev/null
grep -qx 'CompositorCommand=/usr/local/lib/cortetsu/sddm-greeter-compositor --shell=kiosk --config=/etc/sddm/weston.ini' "$sys/etc/sddm.conf" \
    || fail "installer: $(cat "$sys/etc/sddm.conf")"
cmp -s "$sys/etc/sddm.conf.cortetsu-backup" "$WORK/original.conf" || fail "the backup is the original, also after a second run"
cmp -s "$sys/usr/local/lib/cortetsu/sddm-greeter-compositor" "$LAUNCHER" || fail "launcher not installed"
CORTETSU_SYSTEM_ROOT="$sys" bash "$ROOT/scripts/install-sddm-greeter.sh" --remove > /dev/null
cmp -s "$sys/etc/sddm.conf" "$WORK/original.conf" || fail "--remove restores the file"
[[ ! -e "$sys/usr/local/lib/cortetsu/sddm-greeter-compositor" ]] || fail "--remove deletes the launcher"

echo "PASS: the SDDM greeter names the panel's card, retries an early exit, obeys SIGTERM; the installer is reversible"
