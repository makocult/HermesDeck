# AGENTS.md

## Project Role

Hermes Deck is a desktop-first communication shell for a single user's local Hermes Agents. The macOS client is the primary product surface. The Cloud Relay exists only to synchronize clients, route chat-visible messages, store conversation-shell history, and track Agent registry/status metadata.

The Relay must not become a Hermes Agent data platform. Hermes memory, execution artifacts, files, local caches, internal context databases, and non-chat execution logs stay on the device that runs the Agent.

## Current Architecture

- `apps/macos-native`: native SwiftUI macOS client and the current desktop preview target.
- `apps/relay`: TypeScript Fastify relay with PostgreSQL storage and WebSocket routing.
- `packages/shared`: shared TypeScript event and API contracts.
- `apps/connector`: mock and replaceable connector runner path for non-native relay tests.
- `apps/desktop`: older web/Tauri scaffold kept for reference while the product direction moves native-first.
- `scripts`: local preview, build, and acceptance helpers.

## Engineering Rules

- Preserve the data boundary: Relay stores only Deck communication-shell data.
- Do not stop, reset, or mutate a user's local Hermes service unless the task explicitly requires it.
- Prefer the native macOS client for product work. Browser previews are only acceptable for legacy web scaffold checks.
- Keep UI changes consistent with the Figma direction: compact sidebar, 44 px rows, 56 px top bar, system sans-serif, restrained colors, and dark-mode readable controls.
- Use direct, testable changes. Leave unrelated refactors out of feature or fix commits.
- Use `rg` for search and focused file reads before editing.
- Use `apply_patch` for manual source/document edits.
- Do not commit build outputs, local logs, app bundles, `node_modules`, or `.local` preview state.

## Local Development

Start the native preview:

```bash
npm run preview:local
```

Stop preview services:

```bash
npm run preview:stop
```

Build the native macOS app bundle:

```bash
npm run build:native-mac-app
```

The generated app bundle is:

```text
dist/Hermes Deck.app
```

## Validation

Run the relevant checks before handing off:

```bash
swift build --package-path apps/macos-native
npm run build -w @hermes-deck/shared
npm run build -w @hermes-deck/relay
```

For relay routing behavior:

```bash
npm run test -w @hermes-deck/relay
```

For end-to-end local MVP coverage:

```bash
npm run acceptance:local
```

## Local Hermes Agent Workflow

The Add Agent workflow should stay minimal:

- custom name
- custom avatar by clicking the avatar preview
- host/IP
- port
- Detect Local Hermes
- Test Connection

When local Hermes is detected through the TUI Gateway, show host `127.0.0.1`, display port `8642`, and store the actual endpoint as `stdio://tui_gateway.entry` in capabilities/config metadata. Creating or deleting an Agent in Hermes Deck must only affect the Deck shell registration, Direct channel, and message routing records. It must not remove or change the local Hermes installation.
