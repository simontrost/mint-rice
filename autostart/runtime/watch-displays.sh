#!/usr/bin/env bash
# Monitor-change watcher. No cinnamon --replace; no separate root process.
set -Eeuo pipefail
SCRIPT="$HOME/.local/share/mint-rice/runtime/wallpaper-conky.sh"
state() {
  # Include both connector and order; xrandr is already required by wallpaper-conky.sh.
  xrandr --query | awk '$2=="connected" {print $0}'
}
command -v xrandr >/dev/null || exit 1
last="$(state)"
"$SCRIPT"
while sleep 3; do
 next="$(state)"
 if [[ "$next" != "$last" ]]; then
   sleep 2
   next="$(state)"
   if [[ "$next" != "$last" ]]; then
     "$SCRIPT"
     last="$next"
   fi
 fi
done
