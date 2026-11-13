#!/bin/zsh
# Builds ignix-remap, installs it to ~/.local/bin and starts it at login via a LaunchAgent.
# The binary is replaced only when it changed: macOS ties Accessibility permission to the exact binary.
set -euo pipefail
cd "${0:A:h}/.."

LABEL=local.ignix-remap
BIN="$HOME/.local/bin/ignix-remap"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/ignix-remap.log"
BUILD=build/ignix-remap

mkdir -p build "${BIN:h}" "${PLIST:h}" "${LOG:h}"
swiftc -O helper/*.swift shared/*.swift -o "$BUILD"
codesign --force --sign - --identifier "$LABEL" "$BUILD"

launchctl bootout "gui/$UID/$LABEL" 2>/dev/null || true
if ! cmp -s "$BUILD" "$BIN"; then
  cp "$BUILD" "$BIN"
  # Old permission entries stay listed as enabled but no longer apply; remove them in System Settings.
  rm -f "$HOME/Library/Caches/ignix-remap.prompted"
  echo "Installed a new binary: macOS may ask for Accessibility and Input Monitoring again."
fi
sed -e "s|__BIN__|$BIN|" -e "s|__LOG__|$LOG|" "helper/$LABEL.plist" > "$PLIST"
launchctl bootstrap "gui/$UID" "$PLIST"
echo "Started $LABEL. Log: $LOG"
