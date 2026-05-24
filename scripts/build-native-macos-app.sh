#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NATIVE_DIR="$ROOT_DIR/apps/macos-native"
APP_DIR="$ROOT_DIR/dist/Hermes Deck.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$NATIVE_DIR"
swift build -c release

BIN_PATH="$(swift build -c release --show-bin-path)/HermesDeckNative"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BIN_PATH" "$MACOS_DIR/Hermes Deck"
cp "$NATIVE_DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$NATIVE_DIR/Resources/HermesDeckLogo.png" "$RESOURCES_DIR/HermesDeckLogo.png"

ICONSET_DIR="$ROOT_DIR/.local/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$NATIVE_DIR/Resources/HermesDeckLogo.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
cp "$NATIVE_DIR/Resources/HermesDeckLogo.png" "$ICONSET_DIR/icon_512x512@2x.png"
iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"

echo "Built native app: $APP_DIR"

if [[ "${INSTALL_TO_APPLICATIONS:-0}" == "1" ]]; then
  rm -rf "/Applications/Hermes Deck.app"
  cp -R "$APP_DIR" "/Applications/Hermes Deck.app"
  echo "Installed: /Applications/Hermes Deck.app"
fi
