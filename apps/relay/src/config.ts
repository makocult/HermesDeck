export interface RelayConfig {
  databaseUrl: string;
  port: number;
  jwtSecret: string;
  agentRegisterSecret: string;
  seedEmail: string;
  seedPassword: string;
}

export function loadConfig(): RelayConfig {
  return {
    databaseUrl:
      process.env.DATABASE_URL ??
      "postgres://hermes:hermes@localhost:5432/hermes_deck",
    port: Number(process.env.RELAY_PORT ?? 8787),
    jwtSecret: process.env.JWT_SECRET ?? "dev-session-secret",
    agentRegisterSecret:
      process.env.AGENT_REGISTER_SECRET ?? "dev-agent-secret",
    seedEmail: process.env.HERMES_DECK_EMAIL ?? "mako@example.local",
    seedPassword: process.env.HERMES_DECK_PASSWORD ?? "hermes"
  };
}
