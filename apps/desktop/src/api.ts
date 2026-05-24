import type {
  Agent,
  Channel,
  ClientWsEvent,
  CreateChannelRequest,
  LoginResponse,
  Message,
  SendMessageRequest
} from "@hermes-deck/shared";

const relayHttp = import.meta.env.VITE_RELAY_URL ?? "http://localhost:8787";
const relayWs =
  import.meta.env.VITE_RELAY_WS_URL ?? relayHttp.replace(/^http/, "ws");

export interface ApiSession {
  token: string;
}

export async function login(email: string, password: string) {
  return request<LoginResponse>("/api/auth/login", {
    method: "POST",
    body: JSON.stringify({ email, password })
  });
}

export async function listAgents(session: ApiSession) {
  return request<Agent[]>("/api/agents", { session });
}

export async function listChannels(session: ApiSession) {
  return request<Channel[]>("/api/channels", { session });
}

export async function createChannel(session: ApiSession, input: CreateChannelRequest) {
  return request<Channel>("/api/channels", {
    method: "POST",
    session,
    body: JSON.stringify(input)
  });
}

export async function updateChannel(
  session: ApiSession,
  id: string,
  input: Partial<Pick<Channel, "name" | "description" | "routing_mode">> & {
    archived?: boolean;
  }
) {
  return request<Channel>(`/api/channels/${id}`, {
    method: "PATCH",
    session,
    body: JSON.stringify(input)
  });
}

export async function listMessages(session: ApiSession, channelId: string) {
  return request<Message[]>(`/api/channels/${channelId}/messages`, { session });
}

export async function sendMessage(
  session: ApiSession,
  channelId: string,
  input: SendMessageRequest
) {
  return request<Message>(`/api/channels/${channelId}/messages`, {
    method: "POST",
    session,
    body: JSON.stringify(input)
  });
}

export function connectClientSocket(token: string, onEvent: (event: ClientWsEvent) => void) {
  const ws = new WebSocket(`${relayWs}/ws/client?token=${encodeURIComponent(token)}`);
  ws.addEventListener("message", (message) => {
    onEvent(JSON.parse(String(message.data)) as ClientWsEvent);
  });
  return ws;
}

async function request<T>(
  path: string,
  init: RequestInit & { session?: ApiSession } = {}
): Promise<T> {
  const response = await fetch(`${relayHttp}${path}`, {
    ...init,
    headers: {
      "content-type": "application/json",
      ...(init.session ? { authorization: `Bearer ${init.session.token}` } : {}),
      ...init.headers
    }
  });
  if (!response.ok) {
    const error = await response.json().catch(() => ({ error: response.statusText }));
    throw new Error(error.error ?? "Request failed");
  }
  return response.json() as Promise<T>;
}
