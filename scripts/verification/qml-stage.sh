#!/bin/bash
# Render one piece of the Cortetsu shell offscreen, isolated, to a PNG.
#
#   qml-stage.sh BODY.qml OUT.png [SECONDS]
#
# BODY holds `import` lines and the items to place inside `stage` (an Item
# filling a W×HH window, default 1920×1080). The shell runs from a copy of
# cortetsu/ with its own D-Bus session, XDG state/config/cache and no
# Wayland or Hyprland socket, so it cannot touch the running desktop.
# SETUP='cmd' runs inside the private bus 1.5 s after start (notify-send…).
# SEED=DIR copies DIR into the private XDG_STATE_HOME first (history files).
# A hang shows as "NO IMAGE"; the shell log is printed filtered.
set -u
repo=$(cd "$(dirname "$0")/../.." && pwd)
body=$(readlink -f "$1"); out=$(readlink -f "$2"); secs=${3:-4}
work=${QML_STAGE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/cortetsu/qml-stage}
mkdir -p "$work"
rsync -a --delete --exclude target --exclude tests "$repo/cortetsu/" "$work/rt/"
state="$work/state"; rm -rf "$state" "$work/cfg" "$work/cache"; mkdir -p "$state/cortetsu" "$work/cfg" "$work/cache"
[ -n "${SEED:-}" ] && cp -r "$SEED/." "$state/"
# PREFS='{"themeId":"kurogane"}' becomes the private preferences.json.
[ -n "${PREFS:-}" ] && mkdir -p "$work/cfg/cortetsu" && printf '%s' "$PREFS" > "$work/cfg/cortetsu/preferences.json"
{
    echo 'import QtQuick'; echo 'import Quickshell'
    grep '^import' "$body"
    cat <<QML
ShellRoot {
    FloatingWindow {
        implicitWidth: ${W:-1920}; implicitHeight: ${HH:-1080}
        color: "${BG:-#1b1530}"
        Item { id: stage; anchors.fill: parent
            Rectangle { anchors.fill: parent; color: "${BG:-#1b1530}" }
$(grep -v '^import' "$body")
        }
    }
    Timer { running: true; interval: ${secs}000
        onTriggered: stage.grabToImage(result => { result.saveToFile("$out"); Qt.quit(); }) }
}
QML
} > "$work/rt/shell.qml"
rm -f "$out"
env -u WAYLAND_DISPLAY -u HYPRLAND_INSTANCE_SIGNATURE -u DISPLAY \
    XDG_STATE_HOME="$state" XDG_CONFIG_HOME="$work/cfg" XDG_CACHE_HOME="$work/cache" \
    QT_QPA_PLATFORM=offscreen QS_DISABLE_CRASH_HANDLER=1 \
    STAGE_SETUP="${SETUP:-}" timeout $((secs + 10)) dbus-run-session -- sh -c \
        'qs -p "$0" & pid=$!; if [ -n "$STAGE_SETUP" ]; then sleep 1.5; sh -c "$STAGE_SETUP"; fi; wait $pid' \
        "$work/rt/shell.qml" > "$work/log.txt" 2>&1
if [ -s "$out" ]; then echo "OK $out"; else echo "NO IMAGE (hang or error)"; fi
grep -a -E 'WARN|ERROR' "$work/log.txt" | grep -v -i -E 'icon|portal|qmlscanner|pipewire|networkmanager|bluetooth|network:|polkit|WAYLAND_DISPLAY|QT_QPA|--- WARNING|global_shortcuts|GlobalShortcut|window masks|wayland' | head -20
[ -s "$out" ]
