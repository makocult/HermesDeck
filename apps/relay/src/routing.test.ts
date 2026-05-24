import { describe, expect, it } from "vitest";
import type { Channel } from "@hermes-deck/shared";
import { resolveTargets } from "./routing.js";

const baseChannel: Channel = {
  id: "debug",
  name: "debug",
  type: "channel",
  routing_mode: "manual",
  memory_scope: "debug",
  description: null,
  config: {},
  archived_at: null,
  created_at: new Date().toISOString(),
  updated_at: new Date().toISOString(),
  members: [
    {
      id: "mac-hermes",
      name: "Mac Hermes",
      device_type: "macbook",
      host_label: null,
      status: "online",
      capabilities: [],
      default_model: null,
      default_provider: null,
      connector_version: null,
      last_seen_at: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    },
    {
      id: "compute-hermes",
      name: "Compute Hermes",
      device_type: "ubuntu_server",
      host_label: null,
      status: "online",
      capabilities: [],
      default_model: null,
      default_provider: null,
      connector_version: null,
      last_seen_at: null,
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString()
    }
  ]
};

describe("resolveTargets", () => {
  it("routes broadcast to all channel agents", () => {
    expect(resolveTargets({ ...baseChannel, routing_mode: "broadcast" }, "check", undefined).agents).toEqual([
      "mac-hermes",
      "compute-hermes"
    ]);
  });

  it("routes manual mentions to the mentioned agent", () => {
    expect(resolveTargets(baseChannel, "@ComputeHermes check docker", undefined).agents).toEqual([
      "compute-hermes"
    ]);
  });

  it("rejects manual messages without target", () => {
    expect(resolveTargets(baseChannel, "check docker", undefined).error).toMatch(/Manual routing/);
  });
});
