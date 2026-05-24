# Changelog

## 0.1.0 - 2026-05-24

### Added

- Native SwiftUI macOS client at `apps/macos-native`.
- Local preview flow that starts PostgreSQL and the Relay, builds the native app, and opens `dist/Hermes Deck.app`.
- Figma-derived Hermes Deck logo and generated macOS app icon.
- Discord-like desktop shell with Direct and Channels sections, compact sidebar rows, collapsible sidebar, fixed top bar, bottom user profile area, and dark-mode support.
- Direct Agent creation from the sidebar, including name, clickable avatar upload, local Hermes detection, connection testing, and automatic DM creation.
- Direct Agent deletion from Direct settings, archiving the Deck shell registration and DM without touching the local Hermes process.
- Channel creation, editing, member selection, routing mode selection, avatar/icon configuration, and deletion.
- Local Hermes TUI Gateway detection through `~/.hermes/gateway_state.json` and `tui_gateway.entry`, with display port `8642`.
- Native in-app local connector that can register local Hermes Agents with the Relay and stream replies through the Deck message path.
- Agent settings surface for provider, cron, `soul.md`, `user.md`, and skill-oriented configuration views.
- Minimal Cloud Relay data boundary: user/session metadata, Agent registry/status, Direct/Channel definitions, members, messages, message targets, and communication config.
- Relay support for `direct_config` during Agent registration/creation so Direct avatar/icon metadata is written atomically.

### Fixed

- Add Agent no longer fails after uploading an avatar; avatar metadata is sent in the Agent creation request instead of relying on a second channel update.
- Add Agent modal no longer uses unreadable white-on-white input fields in dark mode.
- Avatar upload now happens by clicking the avatar preview instead of using a separate file path field and upload button.
- Detect Local Hermes fills the port field consistently after a successful TUI Gateway probe.
- HTTP DELETE requests no longer send an unnecessary JSON content type when there is no body.
- Preview no longer launches placeholder Compute Hermes by default.

### Verified

- `swift build --package-path apps/macos-native`
- `npm run build -w @hermes-deck/shared`
- `npm run build -w @hermes-deck/relay`
- Manual native-app flow: upload avatar, add local Hermes Agent, verify Direct appears with avatar, delete the test Agent from Direct settings, and confirm the local Hermes Gateway process remains running.
