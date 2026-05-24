export type AgentStatus = "online" | "offline" | "connecting";
export type ChannelType = "direct" | "channel";
export type RoutingMode = "single" | "manual" | "broadcast";
export type SenderType = "user" | "agent" | "system";
export type MessageStatus = "queued" | "delivered" | "completed" | "failed";
export type ContentType = "markdown";

export interface Agent {
  id: string;
  name: string;
  device_type: string;
  host_label: string | null;
  status: AgentStatus;
  capabilities: string[];
  default_model: string | null;
  default_provider: string | null;
  connector_version: string | null;
  archived_at?: string | null;
  last_seen_at: string | null;
  created_at: string;
  updated_at: string;
}

export interface Channel {
  id: string;
  name: string;
  type: ChannelType;
  routing_mode: RoutingMode;
  memory_scope: string | null;
  description: string | null;
  config: Record<string, unknown>;
  archived_at: string | null;
  created_at: string;
  updated_at: string;
  members: Agent[];
  unread_count?: number;
}

export interface MessageTarget {
  agent_id: string;
  status: MessageStatus;
  error: string | null;
  created_at: string;
  updated_at: string;
}

export interface Message {
  id: string;
  channel_id: string;
  sender_type: SenderType;
  sender_id: string;
  content_type: ContentType;
  content: string;
  metadata: Record<string, unknown>;
  status: MessageStatus;
  created_at: string;
  updated_at: string;
  targets: MessageTarget[];
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  user: {
    id: string;
    email: string;
  };
}

export interface RegisterAgentRequest {
  id: string;
  name: string;
  device_type: string;
  host_label?: string;
  capabilities?: string[];
  default_model?: string;
  default_provider?: string;
  connector_version?: string;
  direct_config?: Record<string, unknown>;
}

export interface CreateChannelRequest {
  name: string;
  description?: string;
  members: string[];
  routing_mode: RoutingMode;
  memory_scope?: string;
  config?: Record<string, unknown>;
}

export interface SendMessageRequest {
  content: string;
  content_type: ContentType;
  target_agents?: string[];
}

export interface ClientMessageCreatedEvent {
  type: "message.created";
  channel_id: string;
  message: Message;
}

export interface ClientMessageUpdatedEvent {
  type: "message.updated";
  channel_id: string;
  message: Message;
}

export interface ClientAgentDeltaEvent {
  type: "agent.response.delta";
  channel_id: string;
  message_id: string;
  agent_id: string;
  delta: string;
}

export interface ClientAgentCompletedEvent {
  type: "agent.response.completed";
  channel_id: string;
  message_id: string;
  agent_id: string;
}

export interface ClientAgentStatusChangedEvent {
  type: "agent.status.changed";
  agent_id: string;
  status: AgentStatus;
}

export interface ClientChannelUpdatedEvent {
  type: "channel.updated";
  channel: Channel;
}

export type ClientWsEvent =
  | ClientMessageCreatedEvent
  | ClientMessageUpdatedEvent
  | ClientAgentDeltaEvent
  | ClientAgentCompletedEvent
  | ClientAgentStatusChangedEvent
  | ClientChannelUpdatedEvent;

export interface ConnectorHelloEvent {
  type: "agent.hello";
  agent_id: string;
}

export interface ConnectorHeartbeatEvent {
  type: "agent.heartbeat";
  agent_id: string;
}

export interface ConnectorResponseDeltaEvent {
  type: "agent.response.delta";
  channel_id: string;
  request_message_id: string;
  response_message_id: string;
  agent_id: string;
  delta: string;
}

export interface ConnectorResponseCompletedEvent {
  type: "agent.response.completed";
  channel_id: string;
  request_message_id: string;
  response_message_id: string;
  agent_id: string;
  content: string;
}

export interface ConnectorErrorEvent {
  type: "agent.error";
  channel_id: string;
  request_message_id: string;
  agent_id: string;
  error: string;
}

export type ConnectorToRelayEvent =
  | ConnectorHelloEvent
  | ConnectorHeartbeatEvent
  | ConnectorResponseDeltaEvent
  | ConnectorResponseCompletedEvent
  | ConnectorErrorEvent;

export interface DispatchMessageEvent {
  type: "message.dispatch";
  channel_id: string;
  message_id: string;
  response_message_id: string;
  agent_id: string;
  routing_mode: RoutingMode;
  content: string;
  sender_id: string;
  created_at: string;
}

export type RelayToConnectorEvent = DispatchMessageEvent;

export function isRoutingMode(value: unknown): value is RoutingMode {
  return value === "single" || value === "manual" || value === "broadcast";
}
