#!/bin/zsh
# Builds the FVGKNIX Control settings app and installs it to ~/Applications.
# The app only edits the helper's config, so it needs no permissions and can be rebuilt freely.
set -euo pipefail
cd "${0:A:h}/.."

NAME="FVGKNIX Control"
BUILD="build/$NAME.app"
DEST="$HOME/Applications/$NAME.app"

rm -rf "$BUILD"
mkdir -p "$BUILD/Contents/MacOS" "${DEST:h}"
swiftc -O -parse-as-library app/*.swift shared/*.swift -o "$BUILD/Contents/MacOS/$NAME"
cat > "$BUILD/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>local.ignix-control</string>
  <key>CFBundleName</key><string>$NAME</string>
  <key>CFBundleExecutable</key><string>$NAME</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
EOF
codesign --force --sign - "$BUILD"

pkill -x "$NAME" 2>/dev/null || true
# The app was called IGNIX Control before it was renamed.
pkill -x "IGNIX Control" 2>/dev/null || true
rm -rf "$DEST" "${DEST:h}/IGNIX Control.app"
cp -R "$BUILD" "$DEST"
echo "Installed $DEST"
open "$DEST"
