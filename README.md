# Hermes Deck

Hermes Deck is a desktop-first communication shell for personal Hermes Agents. The Cloud Relay stores only communication-shell data: accounts, agent registry metadata, online state, DM/channel structure, messages, delivery status, and channel routing configuration. Agent-local memory, execution artifacts, files, caches, and internal context databases stay on the device that runs the Agent.

## What Is Implemented

- Tauri 2 + React desktop client scaffold.
- Fastify + PostgreSQL Cloud Relay.
- Agent Connector with a replaceable `HermesRunner` and mock streaming replies.
- Automatic DM creation for registered Agents.
- Channel creation with `single`, `manual`, and `broadcast` routing.
- Client and Agent WebSocket paths.
- Markdown rendering with GFM tables, task lists, code blocks, and copy actions.

## Run Locally

```bash
npm install
docker compose -f infra/docker-compose.yml up -d
npm run dev:relay
```

In separate terminals:

```bash
npm run dev:connector:mac
npm run dev:connector:compute
npm run dev:desktop
```

Open the Vite URL shown by the desktop command. The seeded login is:

- Email: `mako@example.local`
- Password: `hermes`

Tauri native packaging requires Rust and Cargo. This workspace includes the Tauri project files, but the current machine needs a Rust toolchain before `npm run tauri -w @hermes-deck/desktop -- dev` can run.

## Build The macOS App

Hermes Deck is intended to run as a normal macOS app. The development server is only for local iteration.

Install Rust once if `cargo` is missing:

```bash
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
```

Restart the terminal, then build the app bundle:

```bash
npm run build:mac-app
```

The app bundle is copied to:

```text
dist/Hermes Deck.app
```

Install or update it by copying over the app in Applications:

```bash
npm run install:mac-app
```

That command overwrites:

```text
/Applications/Hermes Deck.app
```

The app still needs a reachable Cloud Relay. In local MVP mode, run the Relay and Connectors separately. In normal use, this app should point at your deployed Relay, so double-clicking the app is enough for the client side.

## Local Acceptance

Run the full local acceptance check:

```bash
npm run acceptance:local
```

This opens Docker Desktop if needed, starts PostgreSQL, builds and checks the workspace, starts the Relay and both mock Connectors, then verifies login, automatic DMs, broadcast routing, manual routing, and persisted streamed replies.

## Local Preview

For the easiest development preview:

```bash
npm run preview:local
```

It starts Docker Desktop if needed, runs PostgreSQL on `localhost:55432`, starts the Relay, starts both mock Agent Connectors, starts the desktop preview, runs a smoke check, and opens:

```text
http://localhost:1420
```

Stop the preview:

```bash
npm run preview:stop
```

## Data Boundary

Relay stores:

- account/session metadata
- Agent registry metadata and online status
- Direct and Channel definitions
- Channel members and routing configuration
- chat-visible messages
- message target delivery status

Relay does not store:

- Hermes local memory
- Hermes internal context database
- local execution logs beyond chat-visible replies
- files created or inspected by Agent
- tool execution artifacts
- machine-local caches
