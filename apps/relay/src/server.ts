import cors from "@fastify/cors";
import websocket from "@fastify/websocket";
import Fastify from "fastify";
import { nanoid } from "nanoid";
import { z } from "zod";
import type {
  ClientWsEvent,
  ConnectorToRelayEvent,
  RelayToConnectorEvent
} from "@hermes-deck/shared";
import { Database } from "./db.js";
import { loadConfig } from "./config.js";
import { resolveTargets } from "./routing.js";

const config = loadConfig();
const db = new Database(config.databaseUrl);
const app = Fastify({ logger: true });

const clients = new Set<{ send: (event: ClientWsEvent) => void }>();
const connectors = new Map<string, { send: (event: RelayToConnectorEvent) => void }>();
const responseBuffers = new Map<string, string>();

await db.migrate();
const userId = await db.seedUser(config.seedEmail, config.seedPassword);

await app.register(cors, { origin: true });
await app.register(websocket);

app.get("/health", async () => ({ ok: true }));

app.post("/api/auth/login", async (request, reply) => {
  const body = z
    .object({ email: z.string().email(), password: z.string().min(1) })
    .parse(request.body);
  const session = await db.login(body.email, body.password);
  if (!session) return reply.code(401).send({ error: "Invalid credentials" });
  return session;
});

app.get("/api/agents", { preHandler: requireAuth }, async () => db.listAgents(userId));

app.post("/api/agents/register", async (request, reply) => {
  if (request.headers.authorization !== `Bearer ${config.agentRegisterSecret}`) {
    return reply.code(401).send({ error: "Invalid agent registration token" });
  }
  const body = z
    .object({
      id: z.string().min(1),
      name: z.string().min(1),
      device_type: z.string().min(1),
      host_label: z.string().optional(),
      capabilities: z.array(z.string()).optional(),
      default_model: z.string().optional(),
      default_provider: z.string().optional(),
      connector_version: z.string().optional(),
      direct_config: z.record(z.string(), z.unknown()).optional()
    })
    .parse(request.body);
  const agent = await db.upsertAgent(userId, body);
  broadcast({ type: "agent.status.changed", agent_id: body.id, status: "online" });
  return agent;
});

app.post("/api/agents", { preHandler: requireAuth }, async (request) => {
  const body = z
    .object({
      id: z.string().min(1),
      name: z.string().min(1),
      device_type: z.string().min(1),
      host_label: z.string().optional(),
      capabilities: z.array(z.string()).optional(),
      default_model: z.string().optional(),
      default_provider: z.string().optional(),
      connector_version: z.string().optional(),
      direct_config: z.record(z.string(), z.unknown()).optional()
    })
    .parse(request.body);
  const agent = await db.upsertAgent(userId, body);
  await db.setAgentStatus(body.id, "offline");
  broadcast({ type: "agent.status.changed", agent_id: body.id, status: "offline" });
  return db.getAgent(body.id) ?? agent;
});

app.delete("/api/agents/:id", { preHandler: requireAuth }, async (request) => {
  const params = z.object({ id: z.string().min(1) }).parse(request.params);
  connectors.delete(params.id);
  await db.archiveAgent(userId, params.id);
  broadcast({ type: "agent.status.changed", agent_id: params.id, status: "offline" });
  return { ok: true };
});

app.get("/api/channels", { preHandler: requireAuth }, async () => db.listChannels(userId));

app.post("/api/channels", { preHandler: requireAuth }, async (request, reply) => {
  const body = z
    .object({
      name: z.string().min(1),
      description: z.string().optional(),
      members: z.array(z.string()).min(1),
      routing_mode: z.enum(["single", "manual", "broadcast"]),
      memory_scope: z.string().optional(),
      config: z.record(z.string(), z.unknown()).optional()
    })
    .parse(request.body);
  const channel = await db.createChannel(userId, body);
  if (!channel) return reply.code(500).send({ error: "Channel was not created" });
  broadcast({ type: "channel.updated", channel });
  return channel;
});

app.patch("/api/channels/:id", { preHandler: requireAuth }, async (request, reply) => {
  const params = z.object({ id: z.string() }).parse(request.params);
  const body = z
    .object({
      name: z.string().min(1).optional(),
      description: z.string().optional(),
      routing_mode: z.enum(["single", "manual", "broadcast"]).optional(),
      archived: z.boolean().optional(),
      config: z.record(z.string(), z.unknown()).optional(),
      members: z.array(z.string()).optional()
    })
    .parse(request.body);
  const channel = await db.updateChannel(params.id, body);
  if (!channel) return reply.code(404).send({ error: "Channel not found" });
  broadcast({ type: "channel.updated", channel });
  return channel;
});

app.post("/api/channels/:id/members", { preHandler: requireAuth }, async (request, reply) => {
  const params = z.object({ id: z.string() }).parse(request.params);
  const body = z.object({ agent_id: z.string() }).parse(request.body);
  await db.addChannelMember(params.id, body.agent_id);
  const channel = await db.getChannel(params.id);
  if (!channel) return reply.code(404).send({ error: "Channel not found" });
  broadcast({ type: "channel.updated", channel });
  return channel;
});

app.delete(
  "/api/channels/:id/members/:agentId",
  { preHandler: requireAuth },
  async (request, reply) => {
    const params = z.object({ id: z.string(), agentId: z.string() }).parse(request.params);
    await db.removeChannelMember(params.id, params.agentId);
    const channel = await db.getChannel(params.id);
    if (!channel) return reply.code(404).send({ error: "Channel not found" });
    broadcast({ type: "channel.updated", channel });
    return channel;
  }
);

app.get("/api/channels/:id/messages", { preHandler: requireAuth }, async (request) => {
  const params = z.object({ id: z.string() }).parse(request.params);
  return db.listMessages(params.id);
});

app.post("/api/channels/:id/messages", { preHandler: requireAuth }, async (request, reply) => {
  const params = z.object({ id: z.string() }).parse(request.params);
  const body = z
    .object({
      content: z.string().min(1),
      content_type: z.literal("markdown"),
      target_agents: z.array(z.string()).optional()
    })
    .parse(request.body);
  const channel = await db.getChannel(params.id);
  if (!channel) return reply.code(404).send({ error: "Channel not found" });
  const route = resolveTargets(channel, body.content, body.target_agents);
  const message = await db.createMessage({
    channelId: channel.id,
    senderType: "user",
    senderId: "user",
    contentType: body.content_type,
    content: body.content,
    status: route.error ? "failed" : "delivered",
    metadata: { target_agents: route.agents }
  });
  if (!message) return reply.code(500).send({ error: "Message was not created" });
  broadcast({ type: "message.created", channel_id: channel.id, message });

  if (route.error) {
    const failed = await db.updateMessageContent(message.id, message.content, "failed");
    return reply.code(400).send({ error: route.error, message: failed });
  }

  for (const agentId of route.agents) {
    const connector = connectors.get(agentId);
    const responseMessageId = `msg_${nanoid()}`;
    await db.addMessageTarget(message.id, agentId, connector ? "queued" : "failed", connector ? undefined : "Agent is offline");
    if (!connector) continue;
    const responseMessage = await db.createMessage({
      id: responseMessageId,
      channelId: channel.id,
      senderType: "agent",
      senderId: agentId,
      contentType: "markdown",
      content: "",
      status: "queued",
      metadata: { request_message_id: message.id }
    });
    if (responseMessage) {
      broadcast({ type: "message.created", channel_id: channel.id, message: responseMessage });
    }
    responseBuffers.set(responseMessageId, "");
    connector.send({
      type: "message.dispatch",
      channel_id: channel.id,
      message_id: message.id,
      response_message_id: responseMessageId,
      agent_id: agentId,
      routing_mode: channel.routing_mode,
      content: body.content,
      sender_id: "user",
      created_at: message.created_at
    });
  }
  const updated = await db.getMessage(message.id);
  if (updated) broadcast({ type: "message.updated", channel_id: channel.id, message: updated });
  return updated;
});

app.get("/ws/client", { websocket: true }, async (socket, request) => {
  const token = tokenFromRequest(request);
  const user = token ? await db.userForToken(token) : null;
  if (!user) {
    socket.close(1008, "Unauthorized");
    return;
  }
  const client = {
    send(event: ClientWsEvent) {
      socket.send(JSON.stringify(event));
    }
  };
  clients.add(client);
  socket.on("close", () => clients.delete(client));
});

app.get("/ws/agent", { websocket: true }, async (socket, request) => {
  if (request.headers.authorization !== `Bearer ${config.agentRegisterSecret}`) {
    socket.close(1008, "Unauthorized");
    return;
  }
  const connectionId = nanoid();
  let agentId: string | null = null;

  socket.on("message", async (raw) => {
    const event = JSON.parse(String(raw)) as ConnectorToRelayEvent;
    if (event.type === "agent.hello") {
      agentId = event.agent_id;
      const agent = await db.getAgent(agentId);
      if (!agent) {
        socket.close(1008, "Unknown agent");
        return;
      }
      connectors.set(agentId, { send: (message) => socket.send(JSON.stringify(message)) });
      await db.setAgentStatus(agentId, "online");
      await db.createAgentConnection(agentId, connectionId, request.ip);
      broadcast({ type: "agent.status.changed", agent_id: agentId, status: "online" });
      return;
    }
    if (event.type === "agent.heartbeat") {
      await db.setAgentStatus(event.agent_id, "online");
      return;
    }
    if (event.type === "agent.response.delta") {
      const next = `${responseBuffers.get(event.response_message_id) ?? ""}${event.delta}`;
      responseBuffers.set(event.response_message_id, next);
      await db.updateMessageContent(event.response_message_id, next, "delivered");
      broadcast({
        type: "agent.response.delta",
        channel_id: event.channel_id,
        message_id: event.response_message_id,
        agent_id: event.agent_id,
        delta: event.delta
      });
      return;
    }
    if (event.type === "agent.response.completed") {
      responseBuffers.delete(event.response_message_id);
      const message = await db.updateMessageContent(
        event.response_message_id,
        event.content,
        "completed"
      );
      await db.addMessageTarget(event.request_message_id, event.agent_id, "completed");
      if (message) {
        broadcast({ type: "message.updated", channel_id: event.channel_id, message });
        broadcast({
          type: "agent.response.completed",
          channel_id: event.channel_id,
          message_id: event.response_message_id,
          agent_id: event.agent_id
        });
      }
      return;
    }
    if (event.type === "agent.error") {
      await db.addMessageTarget(event.request_message_id, event.agent_id, "failed", event.error);
      const message = await db.getMessage(event.request_message_id);
      if (message) broadcast({ type: "message.updated", channel_id: event.channel_id, message });
    }
  });

  socket.on("close", async () => {
    if (!agentId) return;
    const closedAgentId = agentId;
    connectors.delete(closedAgentId);
    await db.setAgentStatus(closedAgentId, "offline");
    await db.closeAgentConnection(closedAgentId, connectionId);
    broadcast({ type: "agent.status.changed", agent_id: closedAgentId, status: "offline" });
  });
});

function broadcast(event: ClientWsEvent) {
  for (const client of clients) client.send(event);
}

async function requireAuth(request: { headers: { authorization?: string } }, reply: { code: (statusCode: number) => { send: (body: unknown) => unknown } }) {
  const auth = request.headers.authorization;
  const token = auth?.startsWith("Bearer ") ? auth.slice("Bearer ".length) : null;
  const user = token ? await db.userForToken(token) : null;
  if (!user) return reply.code(401).send({ error: "Unauthorized" });
}

function tokenFromRequest(request: { url: string; headers: { authorization?: string } }) {
  const auth = request.headers.authorization;
  if (auth?.startsWith("Bearer ")) return auth.slice("Bearer ".length);
  const url = new URL(request.url, "http://localhost");
  return url.searchParams.get("token");
}

await app.listen({ port: config.port, host: "0.0.0.0" });
