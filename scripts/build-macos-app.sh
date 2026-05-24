#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Hermes Deck.app"
APP_SOURCE="$ROOT_DIR/apps/desktop/src-tauri/target/release/bundle/macos/$APP_NAME"
APP_DEST="$ROOT_DIR/dist/$APP_NAME"

if ! command -v cargo >/dev/null 2>&1; then
  cat >&2 <<'EOF'
Rust/Cargo is required to build the native macOS app.

Install it once:
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

Then restart the terminal and run:
  npm run build:mac-app
EOF
  exit 1
fi

cd "$ROOT_DIR"
npm run build -w @hermes-deck/shared
npm run tauri -w @hermes-deck/desktop -- build

rm -rf "$APP_DEST"
mkdir -p "$ROOT_DIR/dist"
cp -R "$APP_SOURCE" "$APP_DEST"

echo "Built: $APP_DEST"

if [[ "${INSTALL_TO_APPLICATIONS:-0}" == "1" ]]; then
  rm -rf "/Applications/$APP_NAME"
  cp -R "$APP_DEST" "/Applications/$APP_NAME"
  echo "Installed: /Applications/$APP_NAME"
fi
