#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.local/preview"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
NODE_BIN="$(command -v node)"
DATABASE_URL="${DATABASE_URL:-postgres://hermes:hermes@localhost:55432/hermes_deck}"
RELAY_PORT="${RELAY_PORT:-8787}"
RELAY_URL="${RELAY_URL:-http://localhost:${RELAY_PORT}}"
RELAY_WS_URL="${RELAY_WS_URL:-ws://localhost:${RELAY_PORT}}"
AGENT_SECRET="${AGENT_REGISTER_SECRET:-dev-agent-secret}"
EMAIL="${HERMES_DECK_EMAIL:-mako@example.local}"
PASSWORD="${HERMES_DECK_PASSWORD:-hermes}"

write_launch_agent() {
  local name="$1"
  local program="$2"
  local cwd="$3"
  local log="$4"
  shift 4

  local env_xml=""
  while [[ "$1" != "--" ]]; do
    local key="$1"
    local value="$2"
    shift 2
    env_xml="$env_xml
      <key>$key</key>
      <string>$(xml_escape "$value")</string>"
  done
  shift

  local args_xml=""
  for arg in "$@"; do
    args_xml="$args_xml
    <string>$(xml_escape "$arg")</string>"
  done

  mkdir -p "$LAUNCH_DIR"
  cat >"$LAUNCH_DIR/com.hermesdeck.preview.$name.plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.hermesdeck.preview.$name</string>
  <key>ProgramArguments</key>
  <array>
    <string>$(xml_escape "$program")</string>$args_xml
  </array>
  <key>WorkingDirectory</key>
  <string>$(xml_escape "$cwd")</string>
  <key>EnvironmentVariables</key>
  <dict>$env_xml
  </dict>
  <key>StandardOutPath</key>
  <string>$(xml_escape "$log")</string>
  <key>StandardErrorPath</key>
  <string>$(xml_escape "$log")</string>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
EOF_PLIST
}

xml_escape() {
  printf '%s' "$1" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' -e 's/"/\&quot;/g'
}

mkdir -p "$LOG_DIR"

cd "$ROOT_DIR"

scripts/stop-preview.sh >/dev/null 2>&1 || true

if ! docker version >/dev/null 2>&1; then
  if [[ -d /Applications/Docker.app ]]; then
    echo "Opening Docker Desktop..."
    open -a Docker
  else
    echo "Docker Desktop is required for this local preview." >&2
    exit 1
  fi
  for _ in {1..90}; do
    docker version >/dev/null 2>&1 && break
    sleep 2
  done
fi

if ! docker version >/dev/null 2>&1; then
  echo "Docker is not ready." >&2
  exit 1
fi

echo "Starting local PostgreSQL on localhost:55432..."
docker compose -f infra/docker-compose.yml up -d

if [[ "${HERMES_DECK_RESET_PREVIEW_DB:-1}" == "1" ]]; then
  echo "Resetting local preview data..."
  docker compose -f infra/docker-compose.yml exec -T postgres \
    psql -U hermes -d hermes_deck -c "drop schema public cascade; create schema public;" >/dev/null
fi

echo "Building server packages..."
npm run build -w @hermes-deck/shared
npm run build -w @hermes-deck/relay
npm run build -w @hermes-deck/connector

echo "Starting Relay..."
write_launch_agent "relay" "$NODE_BIN" "$ROOT_DIR" "$LOG_DIR/relay.log" \
  DATABASE_URL "$DATABASE_URL" \
  RELAY_PORT "$RELAY_PORT" \
  JWT_SECRET "${JWT_SECRET:-dev-session-secret}" \
  AGENT_REGISTER_SECRET "$AGENT_SECRET" \
  HERMES_DECK_EMAIL "$EMAIL" \
  HERMES_DECK_PASSWORD "$PASSWORD" \
  -- "$ROOT_DIR/apps/relay/dist/server.js"
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_DIR/com.hermesdeck.preview.relay.plist"

for _ in {1..60}; do
  curl -fsS "$RELAY_URL/health" >/dev/null 2>&1 && break
  sleep 1
done

if ! curl -fsS "$RELAY_URL/health" >/dev/null 2>&1; then
  echo "Relay did not start. See $LOG_DIR/relay.log" >&2
  exit 1
fi

if [[ "${HERMES_DECK_RUN_SMOKE:-0}" == "1" ]]; then
  echo "Running smoke check..."
  RELAY_URL="$RELAY_URL" HERMES_DECK_EMAIL="$EMAIL" HERMES_DECK_PASSWORD="$PASSWORD" \
  node scripts/smoke-e2e.mjs >"$LOG_DIR/smoke.json"
fi

echo "Building native macOS app..."
scripts/build-native-macos-app.sh

echo "Opening native macOS app..."
open "$ROOT_DIR/dist/Hermes Deck.app"

cat <<EOF

Hermes Deck native preview is running.

Open:
  $ROOT_DIR/dist/Hermes Deck.app

Login:
  Email: $EMAIL
  Password: $PASSWORD

What is running:
  Relay:          $RELAY_URL
  PostgreSQL:     localhost:55432
  Agents:         none by default; add local Hermes from Direct +

Logs:
  $LOG_DIR

Stop everything:
  npm run preview:stop
EOF
