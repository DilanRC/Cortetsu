#!/bin/sh
# Once a second: desktop workspace of every nested-compositor window, and the active workspace (read-only).
while :; do
  /usr/bin/hyprctl clients -j | jq -c '.[]|select(.class=="aquamarine" or (.class|startswith("cortetsu-probe")))|[(now|floor),.class,.workspace.id]'
  /usr/bin/hyprctl activeworkspace -j | jq -c '[(now|floor),"active",.id]'
  sleep 1
done
