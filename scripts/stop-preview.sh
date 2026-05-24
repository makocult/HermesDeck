#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.local/preview"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
DOMAIN="gui/$(id -u)"

for name in desktop compute-hermes mac-hermes relay; do
  plist="$LAUNCH_DIR/com.hermesdeck.preview.$name.plist"
  launchctl bootout "$DOMAIN" "$plist" >/dev/null 2>&1 || true
  rm -f "$plist"
done

osascript -e 'tell application "Hermes Deck" to quit' >/dev/null 2>&1 || true
pkill -f "$ROOT_DIR/dist/Hermes Deck.app/Contents/MacOS/Hermes Deck" >/dev/null 2>&1 || true

for port in 8787 1420; do
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    kill "$pid" >/dev/null 2>&1 || true
  done < <(lsof -tiTCP:"$port" -sTCP:LISTEN 2>/dev/null || true)
done

for name in desktop compute-hermes mac-hermes relay; do
  pid_file="$LOG_DIR/$name.pid"
  [[ -f "$pid_file" ]] || continue
  pid="$(cat "$pid_file")"
  if kill -0 "$pid" >/dev/null 2>&1; then
    kill "$pid" >/dev/null 2>&1 || true
  fi
  rm -f "$pid_file"
done

echo "Preview processes stopped."
