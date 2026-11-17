#!/usr/bin/env bash
# Restore user files and dconf from one Mint Rice installer backup.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BACKUP=''
MODE=preview
usage() {
 echo 'Usage: ./restore.sh [--backup PATH] [--apply]'
 echo 'By default this is a preview. --apply restores the saved user files and dconf.'
}
while (( $# )); do
 case "$1" in
   --backup) [[ $# -ge 2 ]] || { usage >&2; exit 2; }; BACKUP="$2"; shift ;;
   --apply) MODE=apply ;;
   --dry-run) MODE=preview ;;
   -h|--help) usage; exit 0 ;;
   *) echo "Unknown flag: $1" >&2; exit 2 ;;
 esac
 shift
done
[[ $EUID -ne 0 ]] || { echo 'Run without sudo.' >&2; exit 1; }
if [[ -z "$BACKUP" ]]; then
 [[ -f "$HOME/.local/share/mint-rice/latest-backup" ]] || { echo 'No latest backup pointer.' >&2; exit 1; }
 BACKUP="$(cat "$HOME/.local/share/mint-rice/latest-backup")"
fi
[[ -f "$BACKUP/manifest.tsv" ]] || { echo "Missing backup manifest: $BACKUP" >&2; exit 1; }
[[ "$BACKUP" == "$HOME/.local/share/mint-rice/backups/"* ]] || { echo 'Backup path is outside Mint Rice backup directory.' >&2; exit 1; }
printf 'Restore from %s (%s)\n' "$BACKUP" "$MODE"
# Reverse operations to correctly restore any repeated dconf prefixes and file changes.
mapfile -t entries < "$BACKUP/manifest.tsv"
for (( i=${#entries[@]}-1; i>=0; i-- )); do
 IFS=$'\t' read -r kind target rel <<< "${entries[$i]}"
 case "$kind" in
   OLD|NEW)
     [[ "$target" == "$HOME/"* ]] || { echo "Refusing non-home target: $target" >&2; exit 1; }
     if [[ "$MODE" == preview ]]; then echo "  [preview] $kind: $target"; continue; fi
     rm -rf -- "$target"
     if [[ "$kind" == OLD ]]; then
       [[ -e "$BACKUP/$rel" || -L "$BACKUP/$rel" ]] || { echo "Missing saved backup: $rel" >&2; exit 1; }
       mkdir -p "$(dirname "$target")"
       cp -a -- "$BACKUP/$rel" "$target"
     fi
     ;;
   DCONF)
     if [[ "$MODE" == preview ]]; then echo "  [preview] restore dconf $target"; continue; fi
     # Clear prefix before loading exact snapshot; otherwise newly installed keys linger.
     dconf reset -f "$target"
     dconf load "$target" < "$BACKUP/$rel"
     ;;
   *) echo "Unrecognized manifest entry: $kind" >&2; exit 1 ;;
 esac
done
if [[ "$MODE" == apply ]]; then
 echo 'User files and dconf restored. Log out and back in if required.'
 echo 'NOTE: This script does not roll back apt installs, cloned engine services or copied /boot GRUB assets.'
else
 echo 'Preview only. Add --apply to restore.'
fi
