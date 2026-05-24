import WebSocket from "ws";
import type {
  ConnectorToRelayEvent,
  DispatchMessageEvent,
  RelayToConnectorEvent
} from "@hermes-deck/shared";
import { getAgentProfile } from "./agents.js";
import { MockHermesRunner } from "./runner.js";

const args = new Map(
  process.argv.slice(2).flatMap((arg, index, all) => {
    if (!arg.startsWith("--")) return [];
    const key = arg.slice(2);
    const value = all[index + 1]?.startsWith("--") ? "true" : all[index + 1] ?? "true";
    return [[key, value]];
  })
);

const agent = getAgentProfile(args.get("agent") ?? process.env.HERMES_AGENT_ID ?? "mac-hermes");
const relayUrl = process.env.RELAY_URL ?? "http://localhost:8787";
const relayWsUrl = process.env.RELAY_WS_URL ?? relayUrl.replace(/^http/, "ws");
const agentSecret = process.env.AGENT_REGISTER_SECRET ?? "dev-agent-secret";
const runner = new MockHermesRunner();

await registerAgent();
connect();

async function registerAgent() {
  const response = await fetch(`${relayUrl}/api/agents/register`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${agentSecret}`
    },
    body: JSON.stringify(agent)
  });
  if (!response.ok) {
    throw new Error(`Agent registration failed: ${response.status} ${await response.text()}`);
  }
}

function connect() {
  const ws = new WebSocket(`${relayWsUrl}/ws/agent`, {
    headers: { authorization: `Bearer ${agentSecret}` }
  });

  ws.on("open", () => {
    send(ws, { type: "agent.hello", agent_id: agent.id });
    setInterval(() => {
      if (ws.readyState === WebSocket.OPEN) {
        send(ws, { type: "agent.heartbeat", agent_id: agent.id });
      }
    }, 10_000);
  });

  ws.on("message", async (raw) => {
    const event = JSON.parse(String(raw)) as RelayToConnectorEvent;
    if (event.type === "message.dispatch") {
      await handleDispatch(ws, event);
    }
  });

  ws.on("close", () => {
    setTimeout(connect, 1_500);
  });

  ws.on("error", (error) => {
    console.error(`[${agent.id}] websocket error`, error.message);
  });
}

async function handleDispatch(ws: WebSocket, event: DispatchMessageEvent) {
  let content = "";
  try {
    for await (const delta of runner.run(event)) {
      content += delta;
      send(ws, {
        type: "agent.response.delta",
        channel_id: event.channel_id,
        request_message_id: event.message_id,
        response_message_id: event.response_message_id,
        agent_id: agent.id,
        delta
      });
    }
    send(ws, {
      type: "agent.response.completed",
      channel_id: event.channel_id,
      request_message_id: event.message_id,
      response_message_id: event.response_message_id,
      agent_id: agent.id,
      content
    });
  } catch (error) {
    send(ws, {
      type: "agent.error",
      channel_id: event.channel_id,
      request_message_id: event.message_id,
      agent_id: agent.id,
      error: error instanceof Error ? error.message : String(error)
    });
  }
}

function send(ws: WebSocket, event: ConnectorToRelayEvent) {
  ws.send(JSON.stringify(event));
}
