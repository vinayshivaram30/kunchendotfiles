#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ln -sfn "$DIR" ~/.dotfiles
# Pull the latest pins first unless that already happened in the last 24h
# (the daily launchd agent usually has). A failed update keeps current pins.
STAMP="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles/last-update"
if [ -z "$(find "$STAMP" -mtime -1 2>/dev/null)" ]; then
  "$DIR/update.sh" || echo "rebuild: update failed (see above); applying current pins" >&2
fi
exec sudo darwin-rebuild switch --flake ~/.dotfiles#mac
