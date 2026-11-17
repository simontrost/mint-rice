#!/usr/bin/env bash
# Mint Rice installer (first preview release)
# Defaults to a read-only preview. Never run with sudo.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODE=preview
WITH_DESKTOP=false
WITH_BASHRC=false
WITH_GRUB=false
WITH_AUTOSTART=false
WITH_ENGINE=false
INSTALL_PACKAGES=false
ONLY=''
BACKUP=''

usage() {
cat <<'HELP'
Usage: ./install.sh [OPTIONS]

Without --apply, everything is a read-only preview.
  --dry-run                Preview only (default)
  --apply                  Actually install selected components, with backups
  --only NAMES             Comma-separated: cinnamon,island,plank,nemo,terminal,conky,btop,wallpapers
  --with-desktop           Set GTK/icon/Cinnamon themes (never import panel layout)
  --with-bashrc            Replace ~/.bashrc (BACKED UP; review first)
  --with-autostart         Enable portable wallpaper/Conky watcher at login
  --install-island-engine  Clone pinned upstream Island engine if not installed (network)
  --install-packages       apt-install known dependencies (requires sudo authentication)
  --with-grub              Copy GRUB theme files (does NOT change /etc/default/grub)
  -h, --help               Show this message

A backup of overwritten user files and dconf is stored below
~/.local/share/mint-rice/backups/<timestamp>/, with a restore.sh manifest.
Dependencies/theme gaps and panel layout are described in README.md.
HELP
}

while (( $# )); do
 case "$1" in
   --dry-run) MODE=preview ;;
   --apply) MODE=apply ;;
   --only) [[ $# -ge 2 ]] || { echo '--only needs a list' >&2; exit 2; }; ONLY=$2; shift ;;
   --with-desktop) WITH_DESKTOP=true ;;
   --with-bashrc) WITH_BASHRC=true ;;
   --with-grub) WITH_GRUB=true ;;
   --with-autostart) WITH_AUTOSTART=true ;;
   --install-island-engine) WITH_ENGINE=true ;;
   --install-packages) INSTALL_PACKAGES=true ;;
   -h|--help) usage; exit 0 ;;
   *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
 esac
 shift
done

if [[ -n "$ONLY" ]]; then
  IFS=',' read -ra requested <<< "$ONLY"
  for requested_component in "${requested[@]}"; do
    case "$requested_component" in
      cinnamon|island|plank|nemo|terminal|conky|btop|wallpapers) ;;
      *) echo "Unknown component: $requested_component" >&2; exit 2 ;;
    esac
  done
fi

[[ ${EUID} -ne 0 ]] || { echo 'Run as your normal user (never sudo ./install.sh).' >&2; exit 1; }
[[ -f "$ROOT/cinnamon/dconf/cinnamon.ini" ]] || { echo "Not a mint-rice checkout: $ROOT" >&2; exit 1; }
[[ "${XDG_CURRENT_DESKTOP:-}" == *Cinnamon* || "${XDG_CURRENT_DESKTOP:-}" == *cinnamon* ]] || \
  echo 'NOTE: Cinnamon desktop not detected; some components may not take effect.'
[[ "${XDG_SESSION_TYPE:-x11}" == x11 ]] || \
  echo 'WARNING: This rice was designed for X11. Cinnamon Island might not work on Wayland.'

has_component() {
 local name="$1"
 [[ -z "$ONLY" ]] && return 0
 [[ ",$ONLY," == *",$name,"* ]]
}

log(){ printf '==> %s\n' "$*"; }
preview(){ if [[ "$MODE" == preview ]]; then printf '  [preview] %s\n' "$*"; return 0; fi; return 1; }

if [[ "$MODE" == apply ]]; then
  stamp="$(date +%Y%m%d-%H%M%S)-$$"
  BACKUP="$HOME/.local/share/mint-rice/backups/$stamp"
  mkdir -p "$BACKUP/saved"
  : > "$BACKUP/manifest.tsv"
  printf '%s\n' "$BACKUP" > "$HOME/.local/share/mint-rice/latest-backup"
  log "Backup: $BACKUP"
else
  log 'DRY RUN only. Add --apply to change files.'
fi

save_path() {
 local dest="$1" id rel
 case "$dest" in
   "$HOME"/*) ;; *) echo "Refusing to overwrite non-home path: $dest" >&2; return 1;;
 esac
 id=$(wc -l < "$BACKUP/manifest.tsv")
 rel="saved/$id"
 if [[ -e "$dest" || -L "$dest" ]]; then
   cp -a -- "$dest" "$BACKUP/$rel"
   printf 'OLD\t%s\t%s\n' "$dest" "$rel" >> "$BACKUP/manifest.tsv"
 else
   printf 'NEW\t%s\t-\n' "$dest" >> "$BACKUP/manifest.tsv"
 fi
}

install_path() {
 local src="$1" dest="$2"
 [[ -e "$src" ]] || { echo "  SKIP (missing): ${src#"$ROOT"/}"; return 0; }
 if preview "${src#"$ROOT"/} -> $dest"; then return 0; fi
 save_path "$dest"
 mkdir -p -- "$(dirname -- "$dest")"
 rm -rf -- "$dest"
 cp -a -- "$src" "$dest"
 printf '  installed %s\n' "$dest"
}

# dconf dumps are not files: keep a separate prefix backup, and restore using dconf load.
import_dconf() {
 local source="$1" prefix="$2" label="$3" dump id
 [[ -s "$source" ]] || { echo "  SKIP empty dconf: $source"; return; }
 if preview "dconf load $prefix (from $label)"; then return 0; fi
 command -v dconf >/dev/null || { echo 'dconf tool missing' >&2; return 1; }
 id=$(wc -l < "$BACKUP/manifest.tsv")
 dump="saved/dconf-$id.ini"
 dconf dump "$prefix" > "$BACKUP/$dump"
 printf 'DCONF\t%s\t%s\n' "$prefix" "$dump" >> "$BACKUP/manifest.tsv"
 dconf load "$prefix" < "$source"
 printf '  imported %s\n' "$prefix"
}

write_file() {
 local target="$1" content="$2"
 if preview "write $target"; then return 0; fi
 save_path "$target"
 mkdir -p "$(dirname "$target")"
 printf '%b\n' "$content" > "$target"
}

if [[ "$INSTALL_PACKAGES" == true ]]; then
  log 'Optional dependencies'
  packages=(plank conky-all feh btop ffmpeg playerctl rsync git gettext pulseaudio-utils python3-gi python3-dateutil)
  if [[ "$MODE" == apply ]]; then
    command -v apt-get >/dev/null || { echo 'apt-get is required for --install-packages' >&2; exit 1; }
    sudo apt-get install "${packages[@]}"
  else
    printf '  [preview] sudo apt-get install %s\n' "${packages[*]}"
  fi
fi

if has_component cinnamon; then
  log 'Cinnamon: theme and extension settings (no panel/dconf snapshot import)'
  install_path "$ROOT/cinnamon/themes/Mintbook-Glass" "$HOME/.themes/Mintbook-Glass"
  for uuid in BlurCinnamon@klangman RoundedCorners@klangman; do
    src="$ROOT/cinnamon/configs/$uuid.json"
    install_path "$src" "$HOME/.config/cinnamon/spices/$uuid/$uuid.json"
  done
  # Do not restore transparent-panels, which clashes with Blur Cinnamon.
  for app in menu@cinnamon.org panel-launchers@cinnamon.org; do
    if [[ -d "$ROOT/cinnamon/applets/$app" ]]; then
      # These contain instance-specific names, so install only by manual review.
      echo "  NOTE: Saved applet settings for $app are not imported automatically."
    fi
  done
  if [[ "$WITH_DESKTOP" == true ]]; then
    log 'Opt-in visual Cinnamon settings (does not touch panels, monitor IDs or keybindings)'
    if [[ "$MODE" == preview ]]; then
      echo '  [preview] cinnamon-theme=Mintbook-Glass, GTK=Mint-Y-Dark-Purple, icons=Colloid-Purple-Catppuccin-Dark'
    else
      for val in 'org.cinnamon.theme name Mintbook-Glass' \
                 'org.cinnamon.desktop.interface gtk-theme Mint-Y-Dark-Purple' \
                 'org.cinnamon.desktop.interface icon-theme Colloid-Purple-Catppuccin-Dark'; do
        read -r schema key value <<< "$val"
        # Save individual current settings as an exact dconf prefix dump.
        prefix='/org/cinnamon/'
        if [[ "$schema" == org.cinnamon.desktop.interface ]]; then prefix='/org/cinnamon/desktop/interface/'; fi
        id=$(wc -l < "$BACKUP/manifest.tsv")
        dconf dump "$prefix" > "$BACKUP/saved/dconf-$id.ini"
        printf 'DCONF\t%s\t%s\n' "$prefix" "saved/dconf-$id.ini" >> "$BACKUP/manifest.tsv"
        gsettings set "$schema" "$key" "$value"
      done
      echo '  Theme settings applied; check installed icon-theme and fonts.'
    fi
  fi
fi

if has_component island; then
  log 'Cinnamon Island (custom extension + settings)'
  if [[ "$WITH_ENGINE" == true ]]; then
    engine_dir="$HOME/.local/share/mint-rice/upstream/cinnamon-island-v0.1.0"
    service="$HOME/.config/systemd/user/cinnamon-island-engine.service"
    if [[ "$MODE" == preview ]]; then
       echo "  [preview] clone v0.1.0 upstream engine to $engine_dir, write user service if absent"
    elif ! systemctl --user cat cinnamon-island-engine.service >/dev/null 2>&1; then
       command -v git >/dev/null || { echo 'git required for engine clone' >&2; exit 1; }
       # Backup both possible paths before creating the clone.
       save_path "$engine_dir"
       mkdir -p "$(dirname "$engine_dir")"
       rm -rf -- "$engine_dir"
       git clone --depth 1 --branch v0.1.0 https://github.com/rovillela-afk/cinnamon-island.git "$engine_dir"
       write_file "$service" "[Unit]
Description=Cinnamon Island engine (mint-rice)

[Service]
Environment=PYTHONSAFEPATH=1
Environment=PYTHONPATH=$engine_dir/engine
ExecStart=/usr/bin/python3 -m cinnamon_island_engine
Restart=on-failure
RestartSec=2"
       systemctl --user daemon-reload
       echo '  Engine service registered. Cinnamon Island starts it on demand.'
    else
       echo '  Existing Cinnamon Island engine detected; left unchanged.'
    fi
  fi
  install_path "$ROOT/cinnamon/island/extension" "$HOME/.local/share/cinnamon/extensions/cinnamon-island@rovillela"
  install_path "$ROOT/cinnamon/configs/cinnamon-island@rovillela.json" \
    "$HOME/.config/cinnamon/spices/cinnamon-island@rovillela/cinnamon-island@rovillela.json"
  echo '  NOTE: Enable Cinnamon Island in System Settings > Extensions.'
  echo '  NOTE: The upstream Python engine must exist; use --install-island-engine on a fresh system.'
fi

if has_component wallpapers; then
  log 'Wallpapers and portable monitor defaults'
  install_path "$ROOT/assets/wallpapers" "$HOME/.local/share/mint-rice/wallpapers"
fi

if has_component plank; then
  log 'Plank: launchers and preferences'
  install_path "$ROOT/plank/launchers" "$HOME/.config/plank/dock1/launchers"
  if [[ -d "$ROOT/plank/themes" ]] && find "$ROOT/plank/themes" -mindepth 1 -print -quit | grep -q .; then
    install_path "$ROOT/plank/themes" "$HOME/.local/share/plank/themes"
  fi
  import_dconf "$ROOT/plank/plank.ini" '/net/launchpad/plank/' 'plank.ini'
  echo '  NOTE: Plank may require restarting or re-login to apply changes.'
fi

if has_component nemo; then
  log 'Nemo: preferences and GTK3 CSS'
  install_path "$ROOT/nemo/gtk.css" "$HOME/.config/gtk-3.0/gtk.css"
  import_dconf "$ROOT/nemo/nemo.ini" '/org/nemo/' 'nemo.ini'
fi

if has_component terminal; then
  log 'Terminal: neofetch, kitty and optional shell/GNOME Terminal settings'
  install_path "$ROOT/terminal/neofetch" "$HOME/.config/neofetch"
  install_path "$ROOT/terminal/kitty" "$HOME/.config/kitty"
  # The GNOME terminal profile is a desktop-specific dconf dump; importing it
  # replaces current profiles, so it is not part of this first installer.
  if [[ "$WITH_BASHRC" == true ]]; then
    install_path "$ROOT/terminal/bash/bashrc" "$HOME/.bashrc"
  else
    echo '  SKIP ~/.bashrc and GNOME Terminal profiles (potentially destructive; manual merge recommended).'
  fi
fi

if has_component conky; then
  log 'Conky: customized Mond configuration'
  # Do not copy upstream .github screenshots or temporary swap files.
  if [[ "$MODE" == preview ]]; then
    echo "  [preview] conky/ -> $HOME/.conky/now-clocking (excluding repository/editor metadata)"
  else
    dest="$HOME/.conky/now-clocking"
    save_path "$dest"
    mkdir -p "$(dirname "$dest")"
    rm -rf -- "$dest"
    mkdir -p "$dest"
    rsync -a --exclude='.github/' --exclude='.git*' --exclude='*.swp' \
      --exclude='*.swo' --exclude='*~' "$ROOT/conky/" "$dest/"
  fi
fi

if has_component btop; then
  log 'btop: custom theme and configuration'
  install_path "$ROOT/btop" "$HOME/.config/btop"
fi

# These portable scripts reference the installed wallpaper/Conky paths.
if has_component wallpapers || has_component conky; then
  log 'Optional runtime monitor scripts (installed, not enabled automatically)'
  install_path "$ROOT/autostart/runtime" "$HOME/.local/share/mint-rice/runtime"
  if [[ "$WITH_AUTOSTART" == true ]]; then
    if [[ -f "$HOME/.config/autostart/Watch display.desktop" ]]; then
      echo '  SKIP enabling second watcher: legacy Watch display.desktop already exists.'
      echo '  Review and disable it before enabling a new watcher.'
    else
      autostart_text="[Desktop Entry]
Type=Application
Name=Mint Rice monitor watcher
Exec=$HOME/.local/share/mint-rice/runtime/watch-displays.sh
Terminal=false
X-GNOME-Autostart-enabled=true"
      write_file "$HOME/.config/autostart/mint-rice-watch.desktop" "$autostart_text"
    fi
  fi
fi

if [[ "$WITH_GRUB" == true ]]; then
  log 'GRUB: copy theme only; do NOT modify active bootloader or /etc/default/grub'
  if [[ "$MODE" == preview ]]; then
    echo '  [preview] sudo cp theme -> /boot/grub/themes/Mintbook-Glass/'
  else
    [[ -d "$ROOT/grub/theme" ]] || { echo 'No GRUB theme in repository' >&2; exit 1; }
    echo '  GRUB files require root. No GRUB config will be edited by this installer.'
    if [[ -e /boot/grub/themes/Mintbook-Glass ]]; then
      echo '  SKIP: /boot/grub/themes/Mintbook-Glass already exists. No overwrite.'
      echo '  Back up or remove it manually if you want to replace it.'
    else
      sudo mkdir -p /boot/grub/themes/Mintbook-Glass
      sudo cp -a "$ROOT/grub/theme/." /boot/grub/themes/Mintbook-Glass/
    fi
    echo '  To activate, back up /etc/default/grub, set GRUB_THEME to /boot/grub/themes/Mintbook-Glass/theme.txt,'
    echo '  then run sudo update-grub. Verify Windows Boot Manager remains present.'
  fi
fi

log 'Done'
if [[ "$MODE" == apply ]]; then
  echo "Backup manifest: $BACKUP/manifest.tsv"
  echo "Undo user-file/dconf changes: $ROOT/restore.sh --backup '$BACKUP'"
  echo 'Log out/in to apply Cinnamon theme and extension changes.'
else
  echo 'No files or system settings changed. Add --apply when satisfied.'
fi
