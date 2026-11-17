#!/usr/bin/env bash
# Export current Linux Mint Cinnamon rice into the repository.
# Run as your normal user, not via sudo.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# Allow running this script from the downloaded file via --repo PATH.
if [[ "${1:-}" == '--repo' ]]; then
    [[ $# -eq 2 ]] || { echo 'Usage: export.sh [--repo /path/to/mint-rice]' >&2; exit 2; }
    ROOT="$(realpath -- "$2")"
fi
[[ -d "$ROOT/.git" ]] || { echo "ERROR: Not a Git repository: $ROOT" >&2; exit 1; }
[[ $EUID -ne 0 ]] || { echo 'ERROR: Run this script without sudo.' >&2; exit 1; }
for cmd in rsync dconf python3; do
    command -v "$cmd" >/dev/null || { echo "ERROR: Missing command: $cmd" >&2; exit 1; }
done

notice() { printf '\n==> %s\n' "$*"; }
copy_file() {
    local src="$1" dst="$2"
    if [[ -f "$src" ]]; then
        mkdir -p -- "$(dirname -- "$ROOT/$dst")"
        cp -a -- "$src" "$ROOT/$dst"
        printf '  %s\n' "$dst"
    else
        printf '  SKIP (not found): %s\n' "$src"
    fi
}
copy_dir() {
    local src="$1" dst="$2"
    if [[ -d "$src" ]]; then
        mkdir -p -- "$ROOT/$dst"
        rsync -a --exclude='.git/' --exclude='__pycache__/' --exclude='*.pyc' \
          --exclude='*.env' --exclude='.env*' --exclude='*.log' --exclude='*.swp' --exclude='*.swo' --exclude='*~' --exclude='*.desktop.disabled' \
          -- "$src/" "$ROOT/$dst/"
        printf '  %s\n' "$dst/"
    else
        printf '  SKIP (not found): %s\n' "$src"
    fi
}
dump_dconf() {
    local path="$1" dst="$2"
    mkdir -p -- "$(dirname -- "$ROOT/$dst")"
    dconf dump "$path" > "$ROOT/$dst"
    printf '  %s\n' "$dst"
}

notice 'Cinnamon, Nemo, Plank and terminal dconf'
dump_dconf /org/cinnamon/ cinnamon/dconf/cinnamon.ini
dump_dconf /org/nemo/ nemo/nemo.ini
dump_dconf /net/launchpad/plank/ plank/plank.ini
dump_dconf /org/gnome/terminal/ terminal/gnome-terminal.ini
# Remove stale Rofi hotkey and machine-only keys from the *exported copy*;
# never change the live Cinnamon configuration.
python3 - "$ROOT/cinnamon/dconf/cinnamon.ini" <<'PY_CINNAMON'
import ast
import re
import sys
from pathlib import Path
p = Path(sys.argv[1])
text = p.read_text()
sections = re.split(r'(?=^\[)', text, flags=re.M)
rofi_ids = set()
cleaned = []
for section in sections:
    match = re.match(r'^\[desktop/keybindings/custom-keybindings/([^]]+)\]', section)
    if match and re.search(r'^command=.*\brofi\b', section, re.M):
        rofi_ids.add(match.group(1))
        continue
    cleaned.append(section)
text = ''.join(cleaned)
if rofi_ids:
    def edit_list(match):
        values = ast.literal_eval(match.group(1))
        return 'custom-list=' + repr([v for v in values if v not in rofi_ids])
    text = re.sub(r'^custom-list=(\[[^\n]*\])$', edit_list, text, flags=re.M)
# Battery model alias and source-machine wallpaper path do not belong in a portable snapshot.
text = re.sub(r'^(?:device-aliases|picture-uri|image-source|night-light-last-coordinates)=.*\n', '', text, flags=re.M)
p.write_text(text)
PY_CINNAMON

notice 'Cinnamon extension configuration'
for id in BlurCinnamon@klangman RoundedCorners@klangman transparent-panels@germanfr; do
    copy_file "$HOME/.config/cinnamon/spices/$id/$id.json" "cinnamon/configs/$id.json"
done
# Extra applet configs which cannot be reconstructed from dconf alone
for id in menu@cinnamon.org panel-launchers@cinnamon.org; do
    copy_dir "$HOME/.config/cinnamon/spices/$id" "cinnamon/applets/$id"
done

notice 'Cinnamon Island: extension code and privacy-filtered settings'
copy_dir "$HOME/.local/share/cinnamon/extensions/cinnamon-island@rovillela" \
    'cinnamon/island/extension'
ISLAND_SRC="$HOME/.config/cinnamon/spices/cinnamon-island@rovillela/cinnamon-island@rovillela.json"
ISLAND_DST="$ROOT/cinnamon/configs/cinnamon-island@rovillela.json"
if [[ -f "$ISLAND_SRC" ]]; then
    mkdir -p -- "$(dirname -- "$ISLAND_DST")"
    python3 - "$ISLAND_SRC" "$ISLAND_DST" <<'PY'
import json
import re
import sys
from pathlib import Path
src, dst = map(Path, sys.argv[1:])
data = json.loads(src.read_text(encoding='utf-8'))
sensitive_key = re.compile(r'(?:calendar[_-]?(?:url|link)|ical|secret|token|password|api[_-]?key|authorization|webcal)', re.I)
sensitive_value = re.compile(r'(?:https?://|webcal://|[\w.+-]+@[\w.-]+\.[A-Za-z]{2,})', re.I)

def clean(obj):
    if isinstance(obj, dict):
        return {k: scrub_value(v) if sensitive_key.search(k) else clean(v)
                for k, v in obj.items()}
    if isinstance(obj, list):
        return [clean(v) for v in obj]
    if isinstance(obj, str) and sensitive_value.search(obj):
        return ''
    return obj

def scrub_value(v):
    # Preserve Cinnamon settings objects (type, description, options), strip only the stored value.
    if isinstance(v, dict) and 'value' in v:
        copy = dict(v)
        copy['value'] = '' if isinstance(v['value'], str) else None
        return clean(copy)
    return '' if isinstance(v, str) else None

out = clean(data)
dst.write_text(json.dumps(out, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print('  cinnamon/configs/cinnamon-island@rovillela.json [filtered; review before commit]')
PY
fi
# Engine state is not copied: it is installed by the upstream package.

notice 'Local Cinnamon theme and GTK overrides'
copy_dir "$HOME/.themes/Mintbook-Glass" 'cinnamon/themes/Mintbook-Glass'
copy_file "$HOME/.config/gtk-3.0/gtk.css" 'nemo/gtk.css'

notice 'GRUB theme and wallpapers (no bootloader files are modified)'
copy_dir '/boot/grub/themes/LiquidGlass-Dark' 'grub/theme'
# Publish only the three space wallpapers traced to DarkShadowShell.
# The source directory may contain personal/third-party images (e.g. retrowave).
# Do not re-import those images during subsequent exports.
for wallpaper in space1.jpg space2.jpg space3.jpg; do
    copy_file "/usr/share/wallpapers/personal/$wallpaper" "assets/wallpapers/$wallpaper"
done

notice 'Plank dock settings, launchers and user themes'
copy_dir "$HOME/.config/plank/dock1/launchers" 'plank/launchers'
copy_dir "$HOME/.local/share/plank/themes" 'plank/themes'

notice 'Terminal, shell, Conky'
copy_file "$HOME/.bashrc" 'terminal/bash/bashrc'
copy_dir "$HOME/.config/neofetch" 'terminal/neofetch'
copy_dir "$HOME/.config/kitty" 'terminal/kitty'
copy_dir "$HOME/.conky/now-clocking" 'conky'

notice 'Autostart and monitor scripts'
copy_dir "$HOME/.config/autostart" 'autostart/desktop'
copy_file "$HOME/dev/scripts/autostart_rice.sh" 'autostart/autostart_rice.sh'
copy_file "$HOME/dev/scripts/watch_displays.sh" 'autostart/watch_displays.sh'
# The keyboard layout script may be personal, so it is intentionally not imported.

echo
echo "==> btop configuration and custom themes"

if [[ -d "$HOME/.config/btop" ]]; then
  copy_dir "$HOME/.config/btop" 'btop'
  # Convert the machine-specific absolute theme path to its portable theme name.
  if [[ -f "$ROOT/btop/btop.conf" ]]; then
    sed -i -E 's|^color_theme[[:space:]]*=[[:space:]]*"[^"]*/([^/"]+)\.theme"|color_theme = "\1"|' "$ROOT/btop/btop.conf"
  fi
else
  echo '  SKIP btop: no ~/.config/btop directory'
fi

notice 'Basic inventory'
{
  printf 'Cinnamon: '; cinnamon --version 2>/dev/null || true
  printf 'Icon theme: '; gsettings get org.cinnamon.desktop.interface icon-theme 2>/dev/null || true
  printf 'GTK theme: '; gsettings get org.cinnamon.desktop.interface gtk-theme 2>/dev/null || true
  printf 'Cinnamon theme: '; gsettings get org.cinnamon.theme name 2>/dev/null || true
  printf 'Extensions: '; gsettings get org.cinnamon enabled-extensions 2>/dev/null || true
  printf 'Panels: '; gsettings get org.cinnamon panels-enabled 2>/dev/null || true
  printf 'Applets: '; gsettings get org.cinnamon enabled-applets 2>/dev/null || true
} > "$ROOT/cinnamon/desktop-state.txt"

notice 'Export complete. No files have been committed or pushed.'
printf '\nReview before publishing: %s\n' "$ROOT"
printf '%s\n' '  - Cinnamon Island calendar URLs and other secrets'
printf '%s\n' '  - .bashrc / Conky scripts / autostart commands'
printf '%s\n' '  - Desktop launchers with absolute user-specific paths'
printf '%s\n' '  - Third-party licenses for GRUB theme and Cinnamon Island'
printf '%s\n' '  - Icon/GTK themes and fonts must be installed separately'
