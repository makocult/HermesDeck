import type { Channel, RoutingMode } from "@hermes-deck/shared";

export interface RouteResult {
  agents: string[];
  error?: string;
}

export function resolveTargets(
  channel: Channel,
  content: string,
  explicitTargets: string[] | undefined
): RouteResult {
  if (channel.members.length === 0) {
    return { agents: [], error: "Channel has no agents." };
  }

  if (channel.routing_mode === "single") {
    if (channel.members.length !== 1) {
      return { agents: [], error: "Single routing requires exactly one agent." };
    }
    return { agents: [channel.members[0].id] };
  }

  if (channel.routing_mode === "broadcast") {
    return { agents: channel.members.map((agent) => agent.id) };
  }

  const manualTargets = explicitTargets?.length
    ? explicitTargets
    : parseMentionTargets(content, channel);
  const known = new Set(channel.members.map((agent) => agent.id));
  const invalid = manualTargets.filter((agentId) => !known.has(agentId));
  if (invalid.length) {
    return { agents: [], error: `Unknown target agent: ${invalid.join(", ")}` };
  }
  if (manualTargets.length === 0) {
    return {
      agents: [],
      error: "Manual routing requires an @Agent mention or target_agents."
    };
  }
  return { agents: [...new Set(manualTargets)] };
}

function parseMentionTargets(content: string, channel: Channel) {
  const compact = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, "");
  const text = compact(content);
  const mentions = new Set<string>();
  for (const agent of channel.members) {
    const aliases = [agent.id, agent.name].map(compact);
    for (const alias of aliases) {
      if (text.includes(alias)) {
        mentions.add(agent.id);
      }
    }
  }
  return [...mentions];
}
