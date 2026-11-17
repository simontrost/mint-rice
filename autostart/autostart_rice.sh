#!/bin/bash

set -u
killall conky 2>/dev/null || true

# --- Output-Namen ---
INTERNAL="eDP"

# --- Pfade ---
WALLPAPER_INTERNAL="/usr/share/wallpapers/personal/space1.jpg"
WALLPAPER_EXTERNAL="/usr/share/wallpapers/personal/space2.jpg"
WALLPAPER_THIRD="/usr/share/wallpapers/personal/space3.jpg"

CONKY_INTERNAL="$HOME/.conky/now-clocking/mond2.conkyrc"
CONKY_EXTERNAL="$HOME/.conky/now-clocking/mond.conkyrc"
CONKY_THIRD="$HOME/.conky/now-clocking/mond3.conkyrc"

set_wallpaper() {
  feh --bg-fill "$@"
}

# --- Externe Outputs automatisch ermitteln (alles "connected", außer INTERNAL) ---
mapfile -t CONNECTED_OUTPUTS < <(xrandr --query | awk '/ connected/{print $1}')
EXTERNALS=()
for o in "${CONNECTED_OUTPUTS[@]}"; do
  [[ "$o" == "$INTERNAL"* ]] && continue
  EXTERNALS+=("$o")
done

EXT_COUNT=${#EXTERNALS[@]}

if (( EXT_COUNT == 0 )); then
  echo "Only internal monitor detected. Loading single monitor setup."

  [ -f "$CONKY_INTERNAL" ] && conky -c "$CONKY_INTERNAL" &
  set_wallpaper "$WALLPAPER_INTERNAL"

elif (( EXT_COUNT == 1 )); then
  echo "One external monitor detected (${EXTERNALS[0]}). Loading dual monitor setup..."

  [ -f "$CONKY_INTERNAL" ] && conky -c "$CONKY_INTERNAL" &
  [ -f "$CONKY_EXTERNAL" ] && conky -c "$CONKY_EXTERNAL" &
  set_wallpaper "$WALLPAPER_INTERNAL" "$WALLPAPER_EXTERNAL"

else
  echo "Two+ external monitors detected (${EXTERNALS[*]}). Loading triple monitor setup..."

  [ -f "$CONKY_INTERNAL" ] && conky -c "$CONKY_INTERNAL" &
  [ -f "$CONKY_EXTERNAL" ] && conky -c "$CONKY_EXTERNAL" &
  [ -f "$CONKY_THIRD"    ] && conky -c "$CONKY_THIRD"    &
  set_wallpaper "$WALLPAPER_INTERNAL" "$WALLPAPER_EXTERNAL" "$WALLPAPER_THIRD"
fi

# optional (ist manchmal overkill, aber wenn du es brauchst, ok)
