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

echo "==> Done: $APP_DIR"

if [[ -n "${DEVELOPER_ID:-}" ]]; then
  echo "==> Code signing with Developer ID: $DEVELOPER_ID"
  xattr -cr "$APP_DIR"
  codesign --force --deep --options runtime --timestamp \
    --sign "$DEVELOPER_ID" "$APP_DIR"

  ZIP="build/${APP_NAME}.zip"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"

  if [[ -n "${AC_PROFILE:-}" ]]; then
    echo "==> Notarizing (keychain profile: $AC_PROFILE)…"
    xcrun notarytool submit "$ZIP" --keychain-profile "$AC_PROFILE" --wait
  elif [[ -n "${AC_APPLE_ID:-}" && -n "${AC_TEAM_ID:-}" && -n "${AC_PASSWORD:-}" ]]; then
    echo "==> Notarizing (apple-id: $AC_APPLE_ID)…"
    xcrun notarytool submit "$ZIP" --apple-id "$AC_APPLE_ID" \
      --team-id "$AC_TEAM_ID" --password "$AC_PASSWORD" --wait
  else
    echo "    Skipping notarization (set AC_PROFILE, or AC_APPLE_ID/AC_TEAM_ID/AC_PASSWORD)."
    echo "    Done: $APP_DIR"
    exit 0
  fi

  echo "==> Stapling ticket…"
  xcrun stapler staple "$APP_DIR"
  ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"
  echo "==> Notarized: $APP_DIR (and $ZIP)"
else
  echo "==> Ad-hoc code signing…"
  codesign --force --deep --sign - "$APP_DIR"
  echo "    Move it to /Applications, or share the .app (recipients: right-click → Open the first time)."
fi
