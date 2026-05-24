import type { RegisterAgentRequest } from "@hermes-deck/shared";

export const agentProfiles: Record<string, RegisterAgentRequest> = {
  "mac-hermes": {
    id: "mac-hermes",
    name: "Mac Hermes",
    device_type: "macbook",
    host_label: "Mako MacBook Air",
    capabilities: ["macos_shell", "filesystem", "local_apps"],
    default_model: "gpt-5.4",
    default_provider: "tokenflux",
    connector_version: "0.1.0"
  },
  "compute-hermes": {
    id: "compute-hermes",
    name: "Compute Hermes",
    device_type: "ubuntu_server",
    host_label: "Local Compute Node",
    capabilities: ["shell", "docker", "git", "cuda", "local_models"],
    default_model: "kimi-2.6",
    default_provider: "tokenflux",
    connector_version: "0.1.0"
  }
};

export function getAgentProfile(id: string) {
  const profile = agentProfiles[id];
  if (!profile) {
    throw new Error(`Unknown agent profile: ${id}`);
  }
  return profile;
}
