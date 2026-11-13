#!/bin/zsh
# Stops ignix-remap and removes everything scripts/install-helper.sh and scripts/install-app.sh put on the system.
set -uo pipefail
LABEL=local.ignix-remap
APP="$HOME/Applications/FVGKNIX Control.app"
OLD_APP="$HOME/Applications/IGNIX Control.app"   # its name before the rename

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null
pkill -x "FVGKNIX Control" 2>/dev/null
pkill -x "IGNIX Control" 2>/dev/null
rm -rf "$APP" "$OLD_APP" "$HOME/Library/Application Support/IGNIX"
rm -f "$HOME/Library/LaunchAgents/$LABEL.plist" "$HOME/.local/bin/ignix-remap" \
  "$HOME/Library/Logs/ignix-remap.log" "$HOME/Library/Caches/ignix-remap.prompted"
defaults delete local.ignix-control 2>/dev/null
rm -f "$HOME/Library/Preferences/local.ignix-control.plist"
rm -rf "$HOME/Library/Saved Application State/local.ignix-control.savedState"
echo "Removed $LABEL, FVGKNIX Control and its settings."
echo "Also remove ignix-remap from Accessibility and Input Monitoring in System Settings."
