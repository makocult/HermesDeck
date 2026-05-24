import Foundation
import SwiftUI

@MainActor
final class DeckStore: ObservableObject {
    private let initialMessagePageSize = 60
    private let olderMessagePageSize = 40
    private let maxMessagesPerChannel = 160

    @Published var token: String?
    @Published var agents: [Agent] = []
    @Published var channels: [Channel] = []
    @Published var selectedChannelId: String?
    @Published var messagesByChannel: [String: [Message]] = [:]
    @Published var isLoadingOlderMessages = false
    @Published var activitiesByMessage: [String: AgentActivity] = [:]
    @Published var slashCommands: [SlashCommand] = SlashCommand.fallbacks
    @Published var isSlashMenuOpen = false
    @Published var draft = ""
    @Published var errorMessage: String?
    @Published var isCreatingChannel = false
    @Published var isAddingAgent = false
    @Published var editingChannel: Channel?
    @Published var settingsAgent: Agent?
    @Published var localHermes = LocalHermesManager()

    let client = RelayClient()
    private var socketTask: URLSessionWebSocketTask?
    private var pendingDeltas: [String: String] = [:]
    private var deltaFlushTask: Task<Void, Never>?
    private var exhaustedHistoryChannels: Set<String> = []

    var selectedChannel: Channel? {
        channels.first { $0.id == selectedChannelId }
    }

    var selectedMessages: [Message] {
        guard let selectedChannelId else { return [] }
        return messagesByChannel[selectedChannelId] ?? []
    }

    func bootstrap() async {
        do {
            let session = try await client.login(email: "mako@example.local", password: "hermes")
            token = session.token
            connectWebSocket()
            await refresh()
            localHermes.startConnectorIfNeeded(store: self)
        } catch {
            errorMessage = "Relay is not reachable. Start local preview services first."
        }
    }

    func refresh() async {
        guard let token else { return }
        do {
            agents = try await client.agents(token: token)
            channels = try await client.channels(token: token)
            if selectedChannelId == nil || !channels.contains(where: { $0.id == selectedChannelId }) {
                selectedChannelId = channels.first(where: { $0.type == "direct" })?.id ?? channels.first?.id
            }
            if let selectedChannelId {
                await loadMessages(channelId: selectedChannelId)
            }
        } catch {
            errorMessage = "Failed to refresh from Relay."
        }
    }

    func select(channel: Channel) {
        selectedChannelId = channel.id
        Task { await loadMessages(channelId: channel.id) }
    }

    func loadMessages(channelId: String) async {
        guard let token else { return }
        do {
            let messages = try await client.messages(token: token, channelId: channelId, limit: initialMessagePageSize)
            messagesByChannel[channelId] = messages
            if messages.count < initialMessagePageSize {
                exhaustedHistoryChannels.insert(channelId)
            } else {
                exhaustedHistoryChannels.remove(channelId)
            }
        } catch {
            errorMessage = "Failed to load messages."
        }
    }

    func loadOlderMessagesIfNeeded(current message: Message) async {
        guard let channelId = selectedChannelId,
              message.id == messagesByChannel[channelId]?.first?.id else { return }
        await loadOlderMessages(channelId: channelId)
    }

    func loadOlderMessages(channelId: String) async {
        guard let token,
              !isLoadingOlderMessages,
              !exhaustedHistoryChannels.contains(channelId),
              let oldest = messagesByChannel[channelId]?.first else { return }
        isLoadingOlderMessages = true
        defer { isLoadingOlderMessages = false }
        do {
            let older = try await client.messages(
                token: token,
                channelId: channelId,
                limit: olderMessagePageSize,
                before: oldest.id
            )
            if older.isEmpty {
                exhaustedHistoryChannels.insert(channelId)
                return
            }
            var existing = messagesByChannel[channelId] ?? []
            let existingIds = Set(existing.map(\.id))
            existing = older.filter { !existingIds.contains($0.id) } + existing
            messagesByChannel[channelId] = trimMessages(existing)
            if older.count < olderMessagePageSize {
                exhaustedHistoryChannels.insert(channelId)
            }
        } catch {
            errorMessage = "Failed to load older messages."
        }
    }

    func sendDraft() async {
        guard let token, let channel = selectedChannel else { return }
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        draft = ""
        do {
            let targets = channel.routing_mode == "manual" ? parseTargets(content: content, channel: channel) : nil
            let message = try await client.sendMessage(
                token: token,
                channelId: channel.id,
                content: content,
                targetAgents: targets
            )
            upsert(message)
        } catch {
            errorMessage = "Message failed. For manual channels, mention an Agent such as @ComputeHermes."
        }
    }

    func loadSlashCommands() async {
        let commands = await localHermes.discoverSlashCommands()
        if !commands.isEmpty {
            slashCommands = commands
        }
    }

    func createChannel(name: String, selectedAgentIds: [String], routingMode: String) async {
        guard let token else { return }
        do {
            let channel = try await client.createChannel(
                token: token,
                name: name,
                members: selectedAgentIds,
                routingMode: routingMode
            )
            channels.append(channel)
            selectedChannelId = channel.id
            isCreatingChannel = false
        } catch {
            errorMessage = "Channel creation failed."
        }
    }

    func createAgent(
        name: String,
        hostLabel: String,
        deviceType: String,
        capabilities: [String],
        defaultModel: String?,
        defaultProvider: String?,
        endpoint: String,
        connectionKind: String,
        icon: String? = nil,
        avatarPath: String? = nil
    ) async {
        guard let token else { return }
        do {
            let id = slug(name)
            _ = try await client.createAgent(
                token: token,
                id: id,
                name: name,
                hostLabel: hostLabel,
                deviceType: deviceType,
                capabilities: capabilities,
                defaultModel: defaultModel,
                defaultProvider: defaultProvider,
                directConfig: directConfig(icon: icon, avatarPath: avatarPath)
            )
            isAddingAgent = false
            await refresh()
            localHermes.startConnectorIfNeeded(store: self)
        } catch {
            errorMessage = "Agent creation failed."
        }
    }

    func deleteAgent(_ agent: Agent) async {
        guard let token else { return }
        do {
            try await client.deleteAgent(token: token, agentId: agent.id)
            localHermes.deleteAPIKey(for: agent.id)
            agents.removeAll { $0.id == agent.id }
            let directId = "dm-\(agent.id)"
            channels.removeAll { $0.id == directId }
            messagesByChannel[directId] = nil
            if selectedChannelId == directId {
                selectedChannelId = channels.first(where: { $0.type == "direct" })?.id ?? channels.first?.id
            }
        } catch {
            errorMessage = "Agent removal failed."
        }
    }

    func updateChannel(
        _ channel: Channel,
        name: String,
        icon: String,
        routingMode: String,
        memberIds: [String],
        avatarPath: String? = nil
    ) async {
        guard let token else { return }
        do {
            let updated = try await client.updateChannel(
                token: token,
                channelId: channel.id,
                name: name,
                routingMode: routingMode,
                members: memberIds,
                icon: icon,
                avatarPath: avatarPath
            )
            if let index = channels.firstIndex(where: { $0.id == updated.id }) {
                channels[index] = updated
            }
            editingChannel = nil
        } catch {
            errorMessage = "Channel update failed."
        }
    }

    func deleteChannel(_ channel: Channel) async {
        guard let token, channel.type == "channel" else { return }
        do {
            try await client.archiveChannel(token: token, channelId: channel.id)
            channels.removeAll { $0.id == channel.id }
            messagesByChannel[channel.id] = nil
            if selectedChannelId == channel.id {
                selectedChannelId = channels.first(where: { $0.type == "direct" })?.id ?? channels.first?.id
            }
        } catch {
            errorMessage = "Channel deletion failed."
        }
    }

    private func connectWebSocket() {
        guard let token else { return }
        var components = URLComponents(url: client.wsURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        let task = URLSession.shared.webSocketTask(with: components.url!)
        socketTask = task
        task.resume()
        receiveNext()
    }

    private func receiveNext() {
        socketTask?.receive { [weak self] result in
            Task { @MainActor in
                guard let self else { return }
                if case let .success(message) = result {
                    if case let .string(text) = message {
                        self.handleEvent(text)
                    }
                    self.receiveNext()
                }
            }
        }
    }

    private func handleEvent(_ text: String) {
        guard let data = text.data(using: .utf8),
              let event = try? JSONDecoder().decode(ClientEvent.self, from: data) else { return }

        switch event {
        case let .messageCreated(_, message), let .messageUpdated(_, message):
            upsert(message)
        case let .responseDelta(channelId, messageId, _, delta):
            enqueueDelta(channelId: channelId, messageId: messageId, delta: delta)
        case let .agentActivity(_, messageId, agentId, kind, phase, text, toolName):
            updateActivity(messageId: messageId, agentId: agentId, kind: kind, phase: phase, text: text, toolName: toolName)
        case .agentStatusChanged, .channelUpdated:
            Task { await refresh() }
        case .ignored:
            break
        }
    }

    private func upsert(_ message: Message) {
        var messages = messagesByChannel[message.channel_id] ?? []
        if let index = messages.firstIndex(where: { $0.id == message.id }) {
            messages[index] = message
        } else {
            messages.append(message)
        }
        messages = trimMessages(messages)
        messagesByChannel[message.channel_id] = messages
    }

    private func updateActivity(messageId: String, agentId: String, kind: String, phase: String, text: String, toolName: String?) {
        if phase == "cleared" {
            if activitiesByMessage[messageId]?.kind == kind {
                activitiesByMessage.removeValue(forKey: messageId)
            }
            return
        }
        activitiesByMessage[messageId] = AgentActivity(
            id: "\(messageId)-\(kind)-\(toolName ?? "activity")",
            messageId: messageId,
            agentId: agentId,
            kind: kind,
            phase: phase,
            text: text,
            toolName: toolName
        )
    }

    private func enqueueDelta(channelId: String, messageId: String, delta: String) {
        let key = "\(channelId)\u{1f}\(messageId)"
        pendingDeltas[key, default: ""] += delta
        guard deltaFlushTask == nil else { return }
        deltaFlushTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            flushPendingDeltas()
        }
    }

    private func flushPendingDeltas() {
        let deltas = pendingDeltas
        pendingDeltas.removeAll()
        deltaFlushTask = nil
        for (key, delta) in deltas {
            let parts = key.split(separator: "\u{1f}", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            appendDelta(channelId: parts[0], messageId: parts[1], delta: delta)
        }
    }

    private func appendDelta(channelId: String, messageId: String, delta: String) {
        var messages = messagesByChannel[channelId] ?? []
        guard let index = messages.firstIndex(where: { $0.id == messageId }) else { return }
        let old = messages[index]
        messages[index] = Message(
            id: old.id,
            channel_id: old.channel_id,
            sender_type: old.sender_type,
            sender_id: old.sender_id,
            content_type: old.content_type,
            content: old.content + delta,
            status: "delivered",
            created_at: old.created_at,
            targets: old.targets
        )
        messages = trimMessages(messages)
        messagesByChannel[channelId] = messages
    }

    private func trimMessages(_ messages: [Message]) -> [Message] {
        guard messages.count > maxMessagesPerChannel else { return messages }
        return Array(messages.suffix(maxMessagesPerChannel))
    }

    private func parseTargets(content: String, channel: Channel) -> [String] {
        let compactContent = compact(content)
        return channel.members
            .filter { compactContent.contains("@\(compact($0.id))") || compactContent.contains("@\(compact($0.name))") }
            .map(\.id)
    }

    private func compact(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func slug(_ value: String) -> String {
        let compacted = value
            .lowercased()
            .map { $0.isLetter || $0.isNumber ? String($0) : "-" }
            .joined()
            .split(separator: "-")
            .joined(separator: "-")
        return compacted.isEmpty ? "agent-\(Int(Date().timeIntervalSince1970))" : compacted
    }

    func slugForDisplayName(_ value: String) -> String {
        slug(value)
    }

    private func directConfig(icon: String?, avatarPath: String?) -> [String: String] {
        var config: [String: String] = [:]
        if let icon, !icon.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config["icon"] = icon
        }
        if let avatarPath, !avatarPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            config["avatar_path"] = avatarPath
        }
        return config
    }
}
