const relayUrl = process.env.RELAY_URL ?? "http://localhost:8787";
const email = process.env.HERMES_DECK_EMAIL ?? "mako@example.local";
const password = process.env.HERMES_DECK_PASSWORD ?? "hermes";

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function request(path, options = {}) {
  const response = await fetch(`${relayUrl}${path}`, {
    ...options,
    headers: {
      "content-type": "application/json",
      ...(options.token ? { authorization: `Bearer ${options.token}` } : {}),
      ...options.headers
    }
  });
  const text = await response.text();
  const body = text ? JSON.parse(text) : null;
  if (!response.ok) {
    throw new Error(`${options.method ?? "GET"} ${path} failed: ${response.status} ${text}`);
  }
  return body;
}

async function waitFor(predicate, label) {
  for (let i = 0; i < 60; i += 1) {
    const value = await predicate();
    if (value) return value;
    await sleep(500);
  }
  throw new Error(`Timed out waiting for ${label}`);
}

const login = await request("/api/auth/login", {
  method: "POST",
  body: JSON.stringify({ email, password })
});
const token = login.token;

const agents = await waitFor(async () => {
  const list = await request("/api/agents", { token });
  const online = new Set(list.filter((agent) => agent.status === "online").map((agent) => agent.id));
  return online.has("compute-hermes") ? list : null;
}, "compute mock agent online");

const directChannels = await waitFor(async () => {
  const list = await request("/api/channels", { token });
  const ids = new Set(list.map((channel) => channel.id));
  return ids.has("dm-compute-hermes") ? list : null;
}, "automatic Direct Messages");

const stamp = Date.now();
const broadcastChannel = await request("/api/channels", {
  method: "POST",
  token,
  body: JSON.stringify({
    name: `e2e-broadcast-${stamp}`,
    members: ["compute-hermes"],
    routing_mode: "broadcast"
  })
});

await request(`/api/channels/${broadcastChannel.id}/messages`, {
  method: "POST",
  token,
  body: JSON.stringify({
    content: "Broadcast acceptance check",
    content_type: "markdown"
  })
});

await waitFor(async () => {
  const messages = await request(`/api/channels/${broadcastChannel.id}/messages`, { token });
  const completedAgents = new Set(
    messages
      .filter((message) => message.sender_type === "agent" && message.status === "completed")
      .map((message) => message.sender_id)
  );
  return completedAgents.has("compute-hermes");
}, "broadcast reply from compute mock agent");

const manualChannel = await request("/api/channels", {
  method: "POST",
  token,
  body: JSON.stringify({
    name: `e2e-manual-${stamp}`,
    members: ["compute-hermes"],
    routing_mode: "manual"
  })
});

await request(`/api/channels/${manualChannel.id}/messages`, {
  method: "POST",
  token,
  body: JSON.stringify({
    content: "@ComputeHermes Manual acceptance check",
    content_type: "markdown"
  })
});

await waitFor(async () => {
  const messages = await request(`/api/channels/${manualChannel.id}/messages`, { token });
  const completedAgents = messages
    .filter((message) => message.sender_type === "agent" && message.status === "completed")
    .map((message) => message.sender_id);
  return completedAgents.length === 1 && completedAgents[0] === "compute-hermes";
}, "manual reply from Compute Hermes only");

console.log(
  JSON.stringify(
    {
      ok: true,
      agents: agents.map((agent) => ({ id: agent.id, status: agent.status })),
      directChannels: directChannels
        .filter((channel) => channel.type === "direct")
        .map((channel) => channel.id),
      broadcastChannel: broadcastChannel.id,
      manualChannel: manualChannel.id
    },
    null,
    2
  )
);
