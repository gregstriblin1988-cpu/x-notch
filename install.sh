#!/bin/bash
# X-Notch for Omarchy installer
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
QS="$HOME/.config/quickshell/xnotch"; BIN="$HOME/.local/bin"; CFG="$HOME/.config/xnotch"
for c in quickshell curl jq; do command -v "$c" >/dev/null || echo "warning: '$c' not found (install it: sudo pacman -S $c)"; done
mkdir -p "$QS" "$BIN" "$CFG" "$HOME/.cache/xnotch"
cp "$SRC"/quickshell/xnotch/* "$QS/"
for f in xnotch xnotch-fetch xnotch-avatar xnotch-toggle; do install -m 755 "$SRC/bin/$f" "$BIN/$f"; done
if [ -e "$CFG/accounts.json" ]; then echo "keeping existing $CFG/accounts.json"; else cp "$SRC/config/accounts.example.json" "$CFG/accounts.json"; echo "created $CFG/accounts.json"; fi
if [ -e "$CFG/token" ]; then echo "keeping existing $CFG/token"; else echo "no token yet: put your X API bearer token in $CFG/token and run: chmod 600 $CFG/token"; fi
cat <<'MSG'

Installed. To start X-Notch at login, add this line to ~/.config/hypr/autostart.lua:

  o.launch_on_start("quickshell -n -p " .. os.getenv("HOME") .. "/.config/quickshell/xnotch")

Start it now with: xnotch on
MSG
