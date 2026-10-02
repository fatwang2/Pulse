#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin_id="pulse.omarchy"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
plugin_home="$config_home/omarchy/plugins"
install_path="$plugin_home/$plugin_id"
# Backups must live outside the plugins directory. Omarchy scans every
# subdirectory of it for a manifest, so a backup left alongside the install is a
# second plugin claiming the same id, and the shell then loads the stale copy.
backup_home="$config_home/omarchy/plugin-backups"
watchlist_dir="$config_home/omarchy/pulse"
watchlist_path="$watchlist_dir/watchlist.json"
restart_shell=true

usage() {
  printf 'Usage: %s [--no-restart]\n' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-restart) restart_shell=false; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done

command -v omarchy >/dev/null 2>&1 || {
  printf '%s\n' 'omarchy is required to install this plugin.' >&2
  exit 1
}

printf '%s\n' 'Validating plugin…'
omarchy plugin validate "$project_dir"

mkdir -p "$plugin_home"
if [[ -L "$install_path" && "$(readlink -f "$install_path")" == "$project_dir" ]]; then
  :
elif [[ -e "$install_path" || -L "$install_path" ]]; then
  mkdir -p "$backup_home"
  backup_path="$backup_home/$plugin_id.bak.$(date +%Y%m%d%H%M%S)"
  mv "$install_path" "$backup_path"
  printf 'Backed up the previous install to %s\n' "$backup_path"
  ln -s "$project_dir" "$install_path"
else
  ln -s "$project_dir" "$install_path"
fi

# The watchlist is seeded only when absent. Overwriting it would throw away the
# one piece of this plugin the user actually owns.
if [[ ! -e "$watchlist_path" ]]; then
  mkdir -p "$watchlist_dir"
  cp "$project_dir/watchlist.example.json" "$watchlist_path"
  printf 'Seeded a starter watchlist at %s\n' "$watchlist_path"
fi

if command -v omarchy-shell >/dev/null 2>&1; then
  omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
  omarchy plugin enable "$plugin_id" >/dev/null 2>&1 || true
fi

if $restart_shell; then
  omarchy restart shell >/dev/null 2>&1 || true
fi

printf 'Pulse installed for development at %s\n' "$install_path"
printf 'Edit %s to change what it watches.\n' "$watchlist_path"
printf '%s\n' 'QML edits are read through the symlink.'
