#!/bin/sh
# Fingerprint of the real Hyprland session (read-only): options, monitors
# (with the workspace each one shows and which one has focus),
# binds and global shortcuts (a leftover temporary bind changes it), and the
# real GameMode transaction file.
for o in general:border_size general:gaps_in decoration:rounding decoration:blur:enabled decoration:shadow:enabled animations:enabled; do /usr/bin/hyprctl getoption $o -j | tr -d '\n '; echo; done
/usr/bin/hyprctl monitors -j | python3 -I -c 'import json,sys;print([(m["name"],m["width"],m["height"],round(m["refreshRate"]),m["scale"],m["activeWorkspace"]["id"],m["focused"]) for m in json.load(sys.stdin)])'
/usr/bin/hyprctl binds -j | python3 -I -c 'import json,sys,hashlib;b=json.load(sys.stdin);print("binds",len(b),hashlib.sha256(json.dumps(b,sort_keys=True).encode()).hexdigest()[:16])'
/usr/bin/hyprctl globalshortcuts | sort | sha256sum | cut -c1-16
ls "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"/cortetsu-gamemode-*.json 2>/dev/null || echo "no-real-gamemode-txn"
