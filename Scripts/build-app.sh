#!/bin/bash
# Builds GPVpnGUI and packages it into a distributable .app bundle.
# Requires the Xcode Command Line Tools (xcode-select --install) — not the full IDE.
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="TunnelBar"
EXECUTABLE="GPVpnGUI"
BUILD_DIR=".build/release"
APP_DIR="build/${APP_NAME}.app"

echo "==> Building (release)…"
swift build -c release

echo "==> Assembling ${APP_DIR}…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BUILD_DIR/$EXECUTABLE" "$APP_DIR/Contents/MacOS/$EXECUTABLE"
cp "Resources/Info.plist"   "$APP_DIR/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc code signing…"
codesign --force --deep --sign - "$APP_DIR"

echo "==> Done: $APP_DIR"
echo "    Move it to /Applications, or share the .app (recipients: right-click → Open the first time)."
