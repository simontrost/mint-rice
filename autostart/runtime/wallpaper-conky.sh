#!/usr/bin/env bash
# X11 wallpaper and Conky profiles for up to three monitors.
set -Eeuo pipefail
HOME_RICE="$HOME/.local/share/mint-rice"
CFG="$HOME/.config/mint-rice/monitors.conf"
INTERNAL_PATTERN='eDP'
WALLPAPER_INTERNAL="$HOME_RICE/wallpapers/space1.jpg"
WALLPAPER_EXTERNAL="$HOME_RICE/wallpapers/space2.jpg"
WALLPAPER_THIRD="$HOME_RICE/wallpapers/space3.jpg"
CONKY_INTERNAL="$HOME/.conky/now-clocking/mond2.conkyrc"
CONKY_EXTERNAL="$HOME/.conky/now-clocking/mond.conkyrc"
CONKY_THIRD="$HOME/.conky/now-clocking/mond3.conkyrc"
[[ -f "$CFG" ]] && source "$CFG"
command -v xrandr >/dev/null || { echo 'xrandr missing'; exit 1; }
command -v feh >/dev/null || { echo 'feh missing'; exit 1; }
mapfile -t outputs < <(xrandr --query | awk '$2=="connected" {print $1}')
[[ ${#outputs[@]} -gt 0 ]] || { echo 'No connected displays'; exit 1; }
external=()
for name in "${outputs[@]}"; do
 [[ "$name" == "$INTERNAL_PATTERN"* ]] || external+=("$name")
done
# feh uses its detected Xinerama monitor order; check assignment if screens differ.
backgrounds=("$WALLPAPER_INTERNAL")
if (( ${#external[@]} >= 1 )); then backgrounds+=("$WALLPAPER_EXTERNAL"); fi
if (( ${#external[@]} >= 2 )); then backgrounds+=("$WALLPAPER_THIRD"); fi
for image in "${backgrounds[@]}"; do [[ -f "$image" ]] || { echo "Missing wallpaper: $image" >&2; exit 1; }; done
# Only stop Conky when the wallpaper script is run by the user/watcher.
command -v conky >/dev/null && pkill -x conky || true
if command -v conky >/dev/null; then
  configs=("$CONKY_INTERNAL")
  if (( ${#external[@]} >= 1 )); then configs+=("$CONKY_EXTERNAL"); fi
  if (( ${#external[@]} >= 2 )); then configs+=("$CONKY_THIRD"); fi
  for cfg in "${configs[@]}"; do [[ -f "$cfg" ]] && { conky -c "$cfg" >/dev/null 2>&1 & }; done
fi
feh --bg-fill "${backgrounds[@]}"
