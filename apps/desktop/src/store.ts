import { create } from "zustand";
import type { Channel, Message } from "@hermes-deck/shared";

interface DeckState {
  token: string | null;
  activeChannelId: string | null;
  messagesByChannel: Record<string, Message[]>;
  setToken(token: string | null): void;
  setActiveChannel(id: string | null): void;
  setMessages(channelId: string, messages: Message[]): void;
  upsertMessage(message: Message): void;
  appendDelta(channelId: string, messageId: string, delta: string): void;
  chooseInitialChannel(channels: Channel[]): void;
}

export const useDeckStore = create<DeckState>((set, get) => ({
  token: localStorage.getItem("hermes.deck.token"),
  activeChannelId: localStorage.getItem("hermes.deck.activeChannel"),
  messagesByChannel: {},
  setToken(token) {
    if (token) localStorage.setItem("hermes.deck.token", token);
    else localStorage.removeItem("hermes.deck.token");
    set({ token });
  },
  setActiveChannel(id) {
    if (id) localStorage.setItem("hermes.deck.activeChannel", id);
    else localStorage.removeItem("hermes.deck.activeChannel");
    set({ activeChannelId: id });
  },
  setMessages(channelId, messages) {
    set((state) => ({
      messagesByChannel: { ...state.messagesByChannel, [channelId]: messages }
    }));
  },
  upsertMessage(message) {
    const current = get().messagesByChannel[message.channel_id] ?? [];
    const exists = current.some((item) => item.id === message.id);
    const next = exists
      ? current.map((item) => (item.id === message.id ? message : item))
      : [...current, message];
    set((state) => ({
      messagesByChannel: { ...state.messagesByChannel, [message.channel_id]: next }
    }));
  },
  appendDelta(channelId, messageId, delta) {
    const current = get().messagesByChannel[channelId] ?? [];
    set((state) => ({
      messagesByChannel: {
        ...state.messagesByChannel,
        [channelId]: current.map((message) =>
          message.id === messageId
            ? { ...message, content: `${message.content}${delta}`, status: "delivered" }
            : message
        )
      }
    }));
  },
  chooseInitialChannel(channels) {
    const active = get().activeChannelId;
    if (active && channels.some((channel) => channel.id === active)) return;
    const first = channels.find((channel) => channel.type === "direct") ?? channels[0];
    if (first) get().setActiveChannel(first.id);
  }
}));
