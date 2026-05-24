#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOG_DIR="$ROOT_DIR/.local/acceptance"
RELAY_URL="${RELAY_URL:-http://localhost:8787}"
RELAY_WS_URL="${RELAY_WS_URL:-ws://localhost:8787}"
EMAIL="${HERMES_DECK_EMAIL:-mako@example.local}"
PASSWORD="${HERMES_DECK_PASSWORD:-hermes}"
AGENT_SECRET="${AGENT_REGISTER_SECRET:-dev-agent-secret}"

mkdir -p "$LOG_DIR"

wait_for_docker() {
  if docker version >/dev/null 2>&1; then
    return
  fi

  if [[ -d /Applications/Docker.app ]]; then
    echo "Opening Docker Desktop..."
    open -a Docker
  else
    echo "Docker Desktop is required for local PostgreSQL acceptance." >&2
    exit 1
  fi

  for _ in {1..90}; do
    if docker version >/dev/null 2>&1; then
      echo "Docker is running."
      return
    fi
    sleep 2
  done

  echo "Docker did not become ready within 180 seconds." >&2
  exit 1
}

wait_for_http() {
  local url="$1"
  for _ in {1..60}; do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return
    fi
    sleep 1
  done
  echo "Timed out waiting for $url" >&2
  exit 1
}

cleanup() {
  for pid_file in "$LOG_DIR"/*.pid; do
    [[ -f "$pid_file" ]] || continue
    local pid
    pid="$(cat "$pid_file")"
    if kill -0 "$pid" >/dev/null 2>&1; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done
}
trap cleanup EXIT

cd "$ROOT_DIR"

wait_for_docker

echo "Starting PostgreSQL..."
docker compose -f infra/docker-compose.yml up -d

echo "Building and checking workspace..."
npm run check
npm test
npm run build

echo "Starting Relay..."
DATABASE_URL="${DATABASE_URL:-postgres://hermes:hermes@localhost:5432/hermes_deck}" \
RELAY_PORT="${RELAY_PORT:-8787}" \
JWT_SECRET="${JWT_SECRET:-dev-session-secret}" \
AGENT_REGISTER_SECRET="$AGENT_SECRET" \
HERMES_DECK_EMAIL="$EMAIL" \
HERMES_DECK_PASSWORD="$PASSWORD" \
npm run start -w @hermes-deck/relay >"$LOG_DIR/relay.log" 2>&1 &
echo "$!" >"$LOG_DIR/relay.pid"

wait_for_http "$RELAY_URL/health"

echo "Starting mock Agent Connectors..."
RELAY_URL="$RELAY_URL" RELAY_WS_URL="$RELAY_WS_URL" AGENT_REGISTER_SECRET="$AGENT_SECRET" \
npm run start -w @hermes-deck/connector -- --agent mac-hermes >"$LOG_DIR/mac-hermes.log" 2>&1 &
echo "$!" >"$LOG_DIR/mac-hermes.pid"

RELAY_URL="$RELAY_URL" RELAY_WS_URL="$RELAY_WS_URL" AGENT_REGISTER_SECRET="$AGENT_SECRET" \
npm run start -w @hermes-deck/connector -- --agent compute-hermes >"$LOG_DIR/compute-hermes.log" 2>&1 &
echo "$!" >"$LOG_DIR/compute-hermes.pid"

node scripts/smoke-e2e.mjs

cat <<EOF

Acceptance passed.

Verified:
- Relay health endpoint
- login
- Agent registration through both Connectors
- automatic Direct Messages
- Channel creation
- broadcast routing to both Agents
- manual routing to Compute Hermes only
- streamed Agent response persisted as messages

Logs:
$LOG_DIR
EOF
