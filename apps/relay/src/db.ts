import { createHash, randomUUID } from "node:crypto";
import pg from "pg";
import type {
  Agent,
  Channel,
  ChannelType,
  ContentType,
  Message,
  MessageStatus,
  RegisterAgentRequest,
  RoutingMode,
  SenderType
} from "@hermes-deck/shared";

const { Pool } = pg;

export class Database {
  readonly pool: pg.Pool;

  constructor(databaseUrl: string) {
    this.pool = new Pool({ connectionString: databaseUrl });
  }

  async migrate() {
    await this.pool.query(`
      create table if not exists users (
        id text primary key,
        email text not null unique,
        password_hash text not null,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );

      create table if not exists sessions (
        token text primary key,
        user_id text not null references users(id) on delete cascade,
        created_at timestamptz not null default now()
      );

      create table if not exists agents (
        id text primary key,
        user_id text not null references users(id) on delete cascade,
        name text not null,
        device_type text not null,
        host_label text,
        status text not null default 'offline',
        capabilities_json jsonb not null default '[]'::jsonb,
        default_model text,
        default_provider text,
        connector_version text,
        archived_at timestamptz,
        last_seen_at timestamptz,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );

      create table if not exists channels (
        id text primary key,
        user_id text not null references users(id) on delete cascade,
        name text not null,
        type text not null,
        routing_mode text not null,
        memory_scope text,
        description text,
        config_json jsonb not null default '{}'::jsonb,
        archived_at timestamptz,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );

      create table if not exists channel_members (
        id text primary key,
        channel_id text not null references channels(id) on delete cascade,
        agent_id text not null references agents(id) on delete cascade,
        role text not null default 'member',
        created_at timestamptz not null default now(),
        unique(channel_id, agent_id)
      );

      create table if not exists messages (
        id text primary key,
        channel_id text not null references channels(id) on delete cascade,
        sender_type text not null,
        sender_id text not null,
        content_type text not null,
        content text not null,
        metadata_json jsonb not null default '{}'::jsonb,
        status text not null default 'delivered',
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now()
      );

      create table if not exists message_targets (
        id text primary key,
        message_id text not null references messages(id) on delete cascade,
        agent_id text not null references agents(id) on delete cascade,
        status text not null,
        error text,
        created_at timestamptz not null default now(),
        updated_at timestamptz not null default now(),
        unique(message_id, agent_id)
      );

      create table if not exists agent_connections (
        id text primary key,
        agent_id text not null references agents(id) on delete cascade,
        connection_id text not null,
        status text not null,
        ip_hash text,
        connected_at timestamptz not null default now(),
        last_heartbeat_at timestamptz,
        disconnected_at timestamptz
      );
    `);
    await this.pool.query("alter table agents add column if not exists archived_at timestamptz");
  }

  async seedUser(email: string, password: string) {
    const existing = await this.pool.query<{ id: string }>(
      "select id from users where email = $1",
      [email]
    );
    if (existing.rowCount) return existing.rows[0].id;
    const id = "user";
    await this.pool.query(
      "insert into users (id, email, password_hash) values ($1, $2, $3)",
      [id, email, hashPassword(password)]
    );
    return id;
  }

  async login(email: string, password: string) {
    const result = await this.pool.query<{
      id: string;
      email: string;
      password_hash: string;
    }>("select id, email, password_hash from users where email = $1", [email]);
    const user = result.rows[0];
    if (!user || user.password_hash !== hashPassword(password)) return null;
    const token = randomUUID();
    await this.pool.query(
      "insert into sessions (token, user_id) values ($1, $2)",
      [token, user.id]
    );
    return { token, user: { id: user.id, email: user.email } };
  }

  async userForToken(token: string) {
    const result = await this.pool.query<{ id: string; email: string }>(
      `select users.id, users.email
       from sessions
       join users on users.id = sessions.user_id
       where sessions.token = $1`,
      [token]
    );
    return result.rows[0] ?? null;
  }

  async upsertAgent(userId: string, input: RegisterAgentRequest) {
    await this.pool.query(
      `insert into agents (
        id, user_id, name, device_type, host_label, status, capabilities_json,
        default_model, default_provider, connector_version, last_seen_at
      )
      values ($1, $2, $3, $4, $5, 'online', $6, $7, $8, $9, now())
      on conflict (id) do update set
        name = excluded.name,
        device_type = excluded.device_type,
        host_label = excluded.host_label,
        status = 'online',
        capabilities_json = excluded.capabilities_json,
        default_model = excluded.default_model,
        default_provider = excluded.default_provider,
        connector_version = excluded.connector_version,
        archived_at = null,
        last_seen_at = now(),
        updated_at = now()`,
      [
        input.id,
        userId,
        input.name,
        input.device_type,
        input.host_label ?? null,
        JSON.stringify(input.capabilities ?? []),
        input.default_model ?? null,
        input.default_provider ?? null,
        input.connector_version ?? null
      ]
    );
    await this.ensureDirectChannel(userId, input.id, input.name, input.direct_config ?? {});
    return this.getAgent(input.id);
  }

  async ensureDirectChannel(userId: string, agentId: string, agentName: string, config: Record<string, unknown> = {}) {
    const id = `dm-${agentId}`;
    await this.pool.query(
      `insert into channels (id, user_id, name, type, routing_mode, memory_scope, config_json)
       values ($1, $2, $3, 'direct', 'single', $1, $4)
       on conflict (id) do update set
        name = excluded.name,
        config_json = excluded.config_json,
        archived_at = null,
        updated_at = now()`,
      [id, userId, agentName, JSON.stringify(config)]
    );
    await this.pool.query(
      `insert into channel_members (id, channel_id, agent_id)
       values ($1, $2, $3)
       on conflict (channel_id, agent_id) do nothing`,
      [`member-${id}-${agentId}`, id, agentId]
    );
  }

  async getAgent(id: string) {
    const result = await this.pool.query("select * from agents where id = $1", [
      id
    ]);
    return result.rows[0] ? mapAgent(result.rows[0]) : null;
  }

  async listAgents(userId: string) {
    const result = await this.pool.query("select * from agents where user_id = $1 and archived_at is null order by name", [
      userId
    ]);
    return result.rows.map(mapAgent);
  }

  async archiveAgent(userId: string, agentId: string) {
    await this.pool.query(
      `update agents
       set archived_at = now(), status = 'offline', updated_at = now()
       where id = $1 and user_id = $2`,
      [agentId, userId]
    );
    await this.pool.query(
      `update channels
       set archived_at = now(), updated_at = now()
       where user_id = $1 and type = 'direct' and id = $2`,
      [userId, `dm-${agentId}`]
    );
    await this.pool.query(
      `delete from channel_members
       where agent_id = $1
         and channel_id in (select id from channels where user_id = $2)`,
      [agentId, userId]
    );
  }

  async setAgentStatus(agentId: string, status: string) {
    await this.pool.query(
      "update agents set status = $2, last_seen_at = now(), updated_at = now() where id = $1",
      [agentId, status]
    );
  }

  async createAgentConnection(agentId: string, connectionId: string, ip?: string) {
    await this.pool.query(
      `insert into agent_connections (id, agent_id, connection_id, status, ip_hash, last_heartbeat_at)
       values ($1, $2, $3, 'online', $4, now())`,
      [randomUUID(), agentId, connectionId, ip ? sha256(ip) : null]
    );
  }

  async closeAgentConnection(agentId: string, connectionId: string) {
    await this.pool.query(
      `update agent_connections
       set status = 'offline', disconnected_at = now()
       where agent_id = $1 and connection_id = $2 and disconnected_at is null`,
      [agentId, connectionId]
    );
  }

  async listChannels(userId: string) {
    const channels = await this.pool.query(
      "select * from channels where user_id = $1 and archived_at is null order by type, name",
      [userId]
    );
    return Promise.all(channels.rows.map((row) => this.hydrateChannel(row)));
  }

  async getChannel(channelId: string) {
    const result = await this.pool.query("select * from channels where id = $1", [
      channelId
    ]);
    return result.rows[0] ? this.hydrateChannel(result.rows[0]) : null;
  }

  async createChannel(
    userId: string,
    input: {
      name: string;
      description?: string;
      members: string[];
      routing_mode: RoutingMode;
      memory_scope?: string;
      config?: Record<string, unknown>;
    }
  ) {
    const id = slugId(input.name);
    await this.pool.query(
      `insert into channels
       (id, user_id, name, type, routing_mode, memory_scope, description, config_json)
       values ($1, $2, $3, 'channel', $4, $5, $6, $7)`,
      [
        id,
        userId,
        input.name,
        input.routing_mode,
        input.memory_scope ?? id,
        input.description ?? null,
        JSON.stringify(input.config ?? {})
      ]
    );
    for (const agentId of input.members) {
      await this.addChannelMember(id, agentId);
    }
    return this.getChannel(id);
  }

  async updateChannel(
    channelId: string,
    input: Partial<{
      name: string;
      description: string;
      routing_mode: RoutingMode;
      archived: boolean;
      config: Record<string, unknown>;
      members: string[];
    }>
  ) {
    const current = await this.getChannel(channelId);
    if (!current) return null;
    await this.pool.query(
      `update channels set
        name = $2,
        description = $3,
        routing_mode = $4,
        config_json = $5,
        archived_at = case when $6 then now() else archived_at end,
        updated_at = now()
       where id = $1`,
      [
        channelId,
        input.name ?? current.name,
        input.description ?? current.description,
        input.routing_mode ?? current.routing_mode,
        JSON.stringify(input.config ?? current.config),
        input.archived ?? false
      ]
    );
    if (input.members) {
      await this.pool.query("delete from channel_members where channel_id = $1", [channelId]);
      for (const agentId of input.members) {
        await this.addChannelMember(channelId, agentId);
      }
    }
    return this.getChannel(channelId);
  }

  async addChannelMember(channelId: string, agentId: string) {
    await this.pool.query(
      `insert into channel_members (id, channel_id, agent_id)
       values ($1, $2, $3)
       on conflict (channel_id, agent_id) do nothing`,
      [randomUUID(), channelId, agentId]
    );
  }

  async removeChannelMember(channelId: string, agentId: string) {
    await this.pool.query(
      "delete from channel_members where channel_id = $1 and agent_id = $2",
      [channelId, agentId]
    );
  }

  async createMessage(input: {
    channelId: string;
    senderType: SenderType;
    senderId: string;
    contentType: ContentType;
    content: string;
    status?: MessageStatus;
    metadata?: Record<string, unknown>;
    id?: string;
  }) {
    const id = input.id ?? `msg_${randomUUID()}`;
    await this.pool.query(
      `insert into messages
       (id, channel_id, sender_type, sender_id, content_type, content, metadata_json, status)
       values ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        id,
        input.channelId,
        input.senderType,
        input.senderId,
        input.contentType,
        input.content,
        JSON.stringify(input.metadata ?? {}),
        input.status ?? "delivered"
      ]
    );
    return this.getMessage(id);
  }

  async updateMessageContent(id: string, content: string, status: MessageStatus) {
    await this.pool.query(
      "update messages set content = $2, status = $3, updated_at = now() where id = $1",
      [id, content, status]
    );
    return this.getMessage(id);
  }

  async addMessageTarget(messageId: string, agentId: string, status: MessageStatus, error?: string) {
    await this.pool.query(
      `insert into message_targets (id, message_id, agent_id, status, error)
       values ($1, $2, $3, $4, $5)
       on conflict (message_id, agent_id) do update set
        status = excluded.status,
        error = excluded.error,
        updated_at = now()`,
      [randomUUID(), messageId, agentId, status, error ?? null]
    );
  }

  async getMessage(id: string) {
    const result = await this.pool.query("select * from messages where id = $1", [
      id
    ]);
    if (!result.rows[0]) return null;
    return this.hydrateMessage(result.rows[0]);
  }

  async listMessages(channelId: string, limit = 80) {
    const result = await this.pool.query(
      `select * from messages
       where channel_id = $1
       order by created_at desc
       limit $2`,
      [channelId, limit]
    );
    const messages = await Promise.all(
      result.rows.reverse().map((row) => this.hydrateMessage(row))
    );
    return messages;
  }

  private async hydrateChannel(row: Record<string, unknown>): Promise<Channel> {
    const members = await this.pool.query(
      `select agents.*
       from channel_members
       join agents on agents.id = channel_members.agent_id
       where channel_members.channel_id = $1 and agents.archived_at is null
       order by agents.name`,
      [row.id]
    );
    return {
      id: String(row.id),
      name: String(row.name),
      type: row.type as ChannelType,
      routing_mode: row.routing_mode as RoutingMode,
      memory_scope: row.memory_scope ? String(row.memory_scope) : null,
      description: row.description ? String(row.description) : null,
      config: (row.config_json ?? {}) as Record<string, unknown>,
      archived_at: row.archived_at ? new Date(String(row.archived_at)).toISOString() : null,
      created_at: new Date(String(row.created_at)).toISOString(),
      updated_at: new Date(String(row.updated_at)).toISOString(),
      members: members.rows.map(mapAgent)
    };
  }

  private async hydrateMessage(row: Record<string, unknown>): Promise<Message> {
    const targets = await this.pool.query(
      "select * from message_targets where message_id = $1 order by created_at",
      [row.id]
    );
    return {
      id: String(row.id),
      channel_id: String(row.channel_id),
      sender_type: row.sender_type as SenderType,
      sender_id: String(row.sender_id),
      content_type: row.content_type as ContentType,
      content: String(row.content),
      metadata: (row.metadata_json ?? {}) as Record<string, unknown>,
      status: row.status as MessageStatus,
      created_at: new Date(String(row.created_at)).toISOString(),
      updated_at: new Date(String(row.updated_at)).toISOString(),
      targets: targets.rows.map((target) => ({
        agent_id: String(target.agent_id),
        status: target.status as MessageStatus,
        error: target.error ? String(target.error) : null,
        created_at: new Date(String(target.created_at)).toISOString(),
        updated_at: new Date(String(target.updated_at)).toISOString()
      }))
    };
  }
}

function mapAgent(row: Record<string, unknown>): Agent {
  return {
    id: String(row.id),
    name: String(row.name),
    device_type: String(row.device_type),
    host_label: row.host_label ? String(row.host_label) : null,
    status: row.status as Agent["status"],
    capabilities: Array.isArray(row.capabilities_json)
      ? (row.capabilities_json as string[])
      : [],
    default_model: row.default_model ? String(row.default_model) : null,
    default_provider: row.default_provider ? String(row.default_provider) : null,
    connector_version: row.connector_version ? String(row.connector_version) : null,
    last_seen_at: row.last_seen_at ? new Date(String(row.last_seen_at)).toISOString() : null,
    archived_at: row.archived_at ? new Date(String(row.archived_at)).toISOString() : null,
    created_at: new Date(String(row.created_at)).toISOString(),
    updated_at: new Date(String(row.updated_at)).toISOString()
  };
}

export function hashPassword(password: string) {
  return sha256(`hermes-deck:${password}`);
}

function sha256(value: string) {
  return createHash("sha256").update(value).digest("hex");
}

function slugId(name: string) {
  const slug = name
    .trim()
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-|-$/g, "");
  return slug || `channel-${randomUUID()}`;
}
