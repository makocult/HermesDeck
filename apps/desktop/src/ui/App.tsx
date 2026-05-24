import type React from "react";
import { useEffect, useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronDown, Copy, Hash, Monitor, Plus, Send, Settings, Wifi, WifiOff } from "lucide-react";
import type { Agent, Channel, Message, RoutingMode } from "@hermes-deck/shared";
import {
  connectClientSocket,
  createChannel,
  listAgents,
  listChannels,
  listMessages,
  login,
  sendMessage
} from "../api";
import { useDeckStore } from "../store";
import { MarkdownView } from "./MarkdownView";

const sessionEmail = "mako@example.local";
const sessionPassword = "hermes";

export function App() {
  const token = useDeckStore((state) => state.token);
  const setToken = useDeckStore((state) => state.setToken);

  if (!token) {
    return <LoginScreen onLogin={setToken} />;
  }
  return <Deck token={token} />;
}

function LoginScreen({ onLogin }: { onLogin: (token: string) => void }) {
  const [email, setEmail] = useState(sessionEmail);
  const [password, setPassword] = useState(sessionPassword);
  const mutation = useMutation({
    mutationFn: () => login(email, password),
    onSuccess: (data) => onLogin(data.token)
  });

  return (
    <main className="login-shell">
      <section className="login-panel">
        <div>
          <p className="eyebrow">Hermes Deck</p>
          <h1>Agent communication, stripped down.</h1>
        </div>
        <label>
          Email
          <input value={email} onChange={(event) => setEmail(event.target.value)} />
        </label>
        <label>
          Password
          <input
            type="password"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
          />
        </label>
        {mutation.error ? <p className="error">{mutation.error.message}</p> : null}
        <button className="primary-button" onClick={() => mutation.mutate()}>
          Open Deck
        </button>
      </section>
    </main>
  );
}

function Deck({ token }: { token: string }) {
  const queryClient = useQueryClient();
  const session = useMemo(() => ({ token }), [token]);
  const activeChannelId = useDeckStore((state) => state.activeChannelId);
  const setActiveChannel = useDeckStore((state) => state.setActiveChannel);
  const chooseInitialChannel = useDeckStore((state) => state.chooseInitialChannel);
  const upsertMessage = useDeckStore((state) => state.upsertMessage);
  const appendDelta = useDeckStore((state) => state.appendDelta);

  const agents = useQuery({
    queryKey: ["agents", token],
    queryFn: () => listAgents(session),
    refetchInterval: 15_000
  });
  const channels = useQuery({
    queryKey: ["channels", token],
    queryFn: () => listChannels(session)
  });

  useEffect(() => {
    if (channels.data) chooseInitialChannel(channels.data);
  }, [channels.data, chooseInitialChannel]);

  useEffect(() => {
    const socket = connectClientSocket(token, (event) => {
      if (event.type === "message.created" || event.type === "message.updated") {
        upsertMessage(event.message);
      }
      if (event.type === "agent.response.delta") {
        appendDelta(event.channel_id, event.message_id, event.delta);
      }
      if (event.type === "agent.status.changed") {
        void queryClient.invalidateQueries({ queryKey: ["agents", token] });
        void queryClient.invalidateQueries({ queryKey: ["channels", token] });
      }
      if (event.type === "channel.updated") {
        void queryClient.invalidateQueries({ queryKey: ["channels", token] });
      }
    });
    return () => socket.close();
  }, [appendDelta, queryClient, token, upsertMessage]);

  const activeChannel = channels.data?.find((channel) => channel.id === activeChannelId) ?? null;

  return (
    <main className="deck-shell">
      <Sidebar
        channels={channels.data ?? []}
        activeChannelId={activeChannelId}
        agents={agents.data ?? []}
        onSelect={setActiveChannel}
        token={token}
      />
      <ChatPane token={token} channel={activeChannel} />
      <SettingsPane agents={agents.data ?? []} />
    </main>
  );
}

function Sidebar({
  channels,
  activeChannelId,
  agents,
  onSelect,
  token
}: {
  channels: Channel[];
  activeChannelId: string | null;
  agents: Agent[];
  onSelect: (id: string) => void;
  token: string;
}) {
  const [creating, setCreating] = useState(false);
  const directs = channels.filter((channel) => channel.type === "direct");
  const normalChannels = channels.filter((channel) => channel.type === "channel");

  return (
    <aside className="sidebar">
      <div className="brand">
        <Monitor size={18} />
        <span>Hermes Deck</span>
      </div>
      <NavSection title="Direct">
        {directs.map((channel) => (
          <ChannelRow
            key={channel.id}
            channel={channel}
            active={channel.id === activeChannelId}
            onSelect={onSelect}
          />
        ))}
      </NavSection>
      <NavSection
        title="Channels"
        action={
          <button className="icon-button" onClick={() => setCreating(true)} title="Create channel">
            <Plus size={16} />
          </button>
        }
      >
        {normalChannels.map((channel) => (
          <ChannelRow
            key={channel.id}
            channel={channel}
            active={channel.id === activeChannelId}
            onSelect={onSelect}
          />
        ))}
      </NavSection>
      {creating ? (
        <CreateChannelDialog token={token} agents={agents} onClose={() => setCreating(false)} />
      ) : null}
    </aside>
  );
}

function NavSection({
  title,
  action,
  children
}: {
  title: string;
  action?: React.ReactNode;
  children: React.ReactNode;
}) {
  return (
    <section className="nav-section">
      <div className="section-title">
        <span>{title}</span>
        {action}
      </div>
      {children}
    </section>
  );
}

function ChannelRow({
  channel,
  active,
  onSelect
}: {
  channel: Channel;
  active: boolean;
  onSelect: (id: string) => void;
}) {
  const online = channel.members.some((agent) => agent.status === "online");
  return (
    <button className={`channel-row ${active ? "active" : ""}`} onClick={() => onSelect(channel.id)}>
      {channel.type === "direct" ? <span className="presence-dot" data-online={online} /> : <Hash size={15} />}
      <span className="channel-name">{channel.name}</span>
      <span className="member-count">{channel.members.length}</span>
    </button>
  );
}

function CreateChannelDialog({
  token,
  agents,
  onClose
}: {
  token: string;
  agents: Agent[];
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [name, setName] = useState("");
  const [routingMode, setRoutingMode] = useState<RoutingMode>("manual");
  const [members, setMembers] = useState<string[]>(agents.map((agent) => agent.id).slice(0, 1));
  const mutation = useMutation({
    mutationFn: () =>
      createChannel(
        { token },
        {
          name,
          routing_mode: routingMode,
          members
        }
      ),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["channels", token] });
      onClose();
    }
  });

  return (
    <div className="modal-backdrop">
      <section className="modal">
        <header>
          <h2>Create Channel</h2>
          <button className="text-button" onClick={onClose}>Close</button>
        </header>
        <label>
          Channel name
          <input value={name} onChange={(event) => setName(event.target.value)} placeholder="two-agents-debug" />
        </label>
        <label>
          Routing mode
          <select value={routingMode} onChange={(event) => setRoutingMode(event.target.value as RoutingMode)}>
            <option value="manual">manual</option>
            <option value="single">single</option>
            <option value="broadcast">broadcast</option>
          </select>
        </label>
        <div className="agent-picker">
          <span>Members</span>
          {agents.map((agent) => (
            <label key={agent.id} className="checkbox-row">
              <input
                type="checkbox"
                checked={members.includes(agent.id)}
                onChange={(event) => {
                  setMembers((current) =>
                    event.target.checked
                      ? [...current, agent.id]
                      : current.filter((id) => id !== agent.id)
                  );
                }}
              />
              {agent.name}
            </label>
          ))}
        </div>
        {mutation.error ? <p className="error">{mutation.error.message}</p> : null}
        <button
          className="primary-button"
          disabled={!name || members.length === 0 || mutation.isPending}
          onClick={() => mutation.mutate()}
        >
          Create
        </button>
      </section>
    </div>
  );
}

function ChatPane({ token, channel }: { token: string; channel: Channel | null }) {
  const messages = useDeckStore((state) =>
    channel ? state.messagesByChannel[channel.id] ?? [] : []
  );
  const setMessages = useDeckStore((state) => state.setMessages);
  const session = useMemo(() => ({ token }), [token]);

  const messageQuery = useQuery({
    queryKey: ["messages", token, channel?.id],
    queryFn: () => listMessages(session, channel!.id),
    enabled: Boolean(channel)
  });

  useEffect(() => {
    if (channel && messageQuery.data) setMessages(channel.id, messageQuery.data);
  }, [channel, messageQuery.data, setMessages]);

  if (!channel) {
    return <section className="chat-pane empty">No channel selected.</section>;
  }

  return (
    <section className="chat-pane">
      <header className="chat-header">
        <div>
          <h1>{channel.type === "channel" ? `# ${channel.name}` : channel.name}</h1>
          <p>{channel.members.map((agent) => agent.name).join(" + ")} · {channel.routing_mode}</p>
        </div>
        <ChevronDown size={18} />
      </header>
      <div className="message-list">
        {messages.map((message) => (
          <MessageBubble key={message.id} message={message} channel={channel} />
        ))}
      </div>
      <Composer token={token} channel={channel} />
    </section>
  );
}

function MessageBubble({ message, channel }: { message: Message; channel: Channel }) {
  const sender =
    message.sender_type === "user"
      ? "You"
      : channel.members.find((agent) => agent.id === message.sender_id)?.name ?? message.sender_id;
  return (
    <article className={`message ${message.sender_type}`}>
      <div className="message-meta">
        <strong>{sender}</strong>
        <span>{new Date(message.created_at).toLocaleTimeString()}</span>
        <span className={`status ${message.status}`}>{message.status}</span>
        <button className="icon-button" title="Copy message" onClick={() => navigator.clipboard.writeText(message.content)}>
          <Copy size={14} />
        </button>
      </div>
      <MarkdownView content={message.content || "_Streaming..._"} />
      {message.targets.some((target) => target.status === "failed") ? (
        <p className="error">{message.targets.find((target) => target.status === "failed")?.error}</p>
      ) : null}
    </article>
  );
}

function Composer({ token, channel }: { token: string; channel: Channel }) {
  const [content, setContent] = useState("");
  const mutation = useMutation({
    mutationFn: () =>
      sendMessage(
        { token },
        channel.id,
        {
          content,
          content_type: "markdown",
          target_agents: parseTargets(content, channel)
        }
      ),
    onSuccess: () => setContent("")
  });

  return (
    <footer className="composer">
      <textarea
        value={content}
        placeholder={channel.routing_mode === "manual" ? "@ComputeHermes check docker logs" : "Message Hermes..."}
        onChange={(event) => setContent(event.target.value)}
        onKeyDown={(event) => {
          if ((event.metaKey || event.ctrlKey) && event.key === "Enter" && content.trim()) {
            mutation.mutate();
          }
        }}
      />
      <button
        className="send-button"
        disabled={!content.trim() || mutation.isPending}
        onClick={() => mutation.mutate()}
        title="Send"
      >
        <Send size={18} />
      </button>
      {mutation.error ? <p className="error">{mutation.error.message}</p> : null}
    </footer>
  );
}

function SettingsPane({ agents }: { agents: Agent[] }) {
  return (
    <aside className="settings-pane">
      <div className="settings-title">
        <Settings size={17} />
        <span>Settings</span>
      </div>
      <section>
        <h2>Agents</h2>
        {agents.map((agent) => (
          <div className="agent-row" key={agent.id}>
            {agent.status === "online" ? <Wifi size={15} /> : <WifiOff size={15} />}
            <div>
              <strong>{agent.name}</strong>
              <span>{agent.host_label ?? agent.device_type}</span>
            </div>
          </div>
        ))}
      </section>
      <section>
        <h2>Cloud Relay</h2>
        <p>Communication and chat history only.</p>
      </section>
      <section>
        <h2>Appearance</h2>
        <p>Dark mode is enabled for MVP.</p>
      </section>
    </aside>
  );
}

function parseTargets(content: string, channel: Channel) {
  if (channel.routing_mode !== "manual") return undefined;
  const compact = (value: string) => value.toLowerCase().replace(/[^a-z0-9]/g, "");
  return channel.members
    .filter((agent) => {
      const text = compact(content);
      return [agent.id, agent.name].some((alias) => text.includes(`@${compact(alias)}`));
    })
    .map((agent) => agent.id);
}
