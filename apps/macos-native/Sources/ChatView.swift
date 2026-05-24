import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var store: DeckStore
    @Binding var isSidebarCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(isSidebarCollapsed: $isSidebarCollapsed)
            TimelineView()
            ComposerView()
        }
        .background(DeckColor.surface)
    }
}

struct TimelineView: View {
    @EnvironmentObject private var store: DeckStore

    // Kept as a component boundary so the timeline can move to an AppKit-backed
    // virtualized list without changing ChatView or message rendering callers.
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DeckMetrics.spacing16) {
                    if store.isLoadingOlderMessages {
                        HStack {
                            Spacer()
                            ProgressView()
                                .controlSize(.small)
                            Spacer()
                        }
                        .padding(.vertical, DeckMetrics.spacing8)
                    }
                    ForEach(store.selectedMessages) { message in
                        MessageView(message: message)
                            .id(message.id)
                            .onAppear {
                                Task { await store.loadOlderMessagesIfNeeded(current: message) }
                            }
                    }
                }
                .padding(.horizontal, DeckMetrics.spacing24)
                .padding(.vertical, DeckMetrics.spacing12)
            }
            .onChange(of: store.selectedMessages.count) { _, _ in
                if let last = store.selectedMessages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }
}

struct ChatHeader: View {
    @EnvironmentObject private var store: DeckStore
    @Binding var isSidebarCollapsed: Bool

    private var memberStatus: String {
        guard let channel = store.selectedChannel else { return "offline" }
        if channel.members.contains(where: { $0.status == "online" }) { return "online" }
        if channel.members.contains(where: { $0.status == "connecting" }) { return "connecting" }
        return "offline"
    }

    private var signalColor: Color {
        switch memberStatus {
        case "online": DeckColor.online
        case "connecting": .orange
        default: DeckColor.muted
        }
    }

    var body: some View {
        HStack {
            if isSidebarCollapsed {
                Button {
                    isSidebarCollapsed = false
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: DeckTypography.title, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            Text(store.selectedChannel?.name ?? "No Channel")
                .font(.system(size: DeckTypography.control, weight: .regular))
                .foregroundStyle(DeckColor.headerText)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "cellularbars")
                    .font(.system(size: DeckTypography.control, weight: .regular))
                    .foregroundStyle(signalColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(memberStatus == "online" ? "Agent online" : "Agent offline")
        }
        .frame(height: DeckMetrics.topBarHeight)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, DeckMetrics.spacing24)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeckColor.border)
                .frame(height: 1)
        }
    }
}

struct MessageView: View {
    @EnvironmentObject private var store: DeckStore
    let message: Message

    var senderName: String {
        if message.sender_type == "user" { return "You" }
        return store.agents.first(where: { $0.id == message.sender_id })?.name ?? message.sender_id
    }

    var body: some View {
        if message.sender_type == "user" {
            UserMessageView(message: message)
        } else {
            AgentMessageView(message: message, senderName: senderName)
        }
    }
}

struct AgentMessageView: View {
    @EnvironmentObject private var store: DeckStore
    let message: Message
    let senderName: String

    private var senderChannel: Channel? {
        store.channels.first { channel in
            channel.type == "direct" && channel.members.contains { $0.id == message.sender_id }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: DeckMetrics.spacing6) {
            MessageAvatar(channel: senderChannel, fallbackName: senderName)
            VStack(alignment: .leading, spacing: 4) {
                MessageHeader(senderName: senderName, createdAt: message.created_at)
                if let activity = store.activitiesByMessage[message.id] {
                    AgentActivityView(activity: activity)
                } else if message.isStreaming {
                    AgentTypingView()
                }
                MarkdownBody(content: message.isStreaming ? "_Streaming..._" : message.content, baseFontSize: DeckTypography.body)
                MessageFailureView(message: message)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgentTypingView: View {
    var body: some View {
        HStack(spacing: DeckMetrics.spacing6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
            Text("输入中...")
                .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                .foregroundStyle(DeckColor.muted)
        }
    }
}

struct AgentActivityView: View {
    let activity: AgentActivity

    var body: some View {
        HStack(spacing: DeckMetrics.spacing6) {
            Image(systemName: iconName)
                .font(.system(size: DeckTypography.meta, weight: .medium))
                .foregroundStyle(activity.isActive ? DeckColor.online : DeckColor.muted)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: DeckTypography.meta, weight: .medium))
                    .foregroundStyle(DeckColor.text)
                if !activity.text.isEmpty {
                    Text(activity.text)
                        .font(.system(size: DeckTypography.meta, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, DeckMetrics.spacing8)
        .padding(.vertical, DeckMetrics.spacing6)
        .background(DeckColor.composer)
        .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.radius8, style: .continuous))
    }

    private var iconName: String {
        activity.kind == "tool" ? "wrench.and.screwdriver" : "waveform"
    }

    private var title: String {
        if activity.kind == "tool" {
            return activity.toolName.map { "Tool: \($0)" } ?? "Tool"
        }
        return activity.phase == "completed" ? "已完成" : "输入中..."
    }
}

struct UserMessageView: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: DeckMetrics.spacing6) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: DeckMetrics.spacing8) {
                    Text(message.created_at.formattedMessageTime())
                        .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                }
                MarkdownBody(content: message.content, fillsWidth: false)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, DeckMetrics.spacing12)
                    .padding(.vertical, DeckMetrics.spacing8)
                    .background(DeckColor.selectedRow)
                    .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.radius16, style: .continuous))
                MessageFailureView(message: message)
            }
            MessageAvatar()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct MessageHeader: View {
    let senderName: String
    let createdAt: String

    var body: some View {
        HStack(spacing: DeckMetrics.spacing24) {
            Text(senderName)
                .font(.system(size: DeckTypography.bodySmall, weight: .semibold))
                .foregroundStyle(DeckColor.text)
            Text(createdAt.formattedMessageTime())
                .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                .foregroundStyle(DeckColor.muted)
            Spacer(minLength: 0)
        }
    }
}

struct MessageAvatar: View {
    var channel: Channel?
    var fallbackName = ""

    var body: some View {
        ZStack {
            Circle()
                .fill(DeckColor.avatar)
            if let avatarPath = channel?.avatarPath,
               let image = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: DeckMetrics.avatarSize, height: DeckMetrics.avatarSize)
                    .clipShape(Circle())
            } else if let icon = channel?.icon, icon != "#" && icon != "●" {
                Text(icon)
                    .font(.system(size: DeckTypography.body, weight: .semibold))
                    .foregroundStyle(.white)
            } else if !fallbackName.isEmpty {
                Text(String(fallbackName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                    .font(.system(size: DeckTypography.body, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: DeckMetrics.avatarSize, height: DeckMetrics.avatarSize)
    }
}

struct CopyMessageButton: View {
    let content: String

    var body: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(content, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc")
                .font(.system(size: DeckTypography.bodySmall))
                .foregroundStyle(DeckColor.muted)
        }
        .buttonStyle(.plain)
    }
}

struct MessageFailureView: View {
    let message: Message

    var body: some View {
        if let failed = message.targets.first(where: { $0.status == "failed" }) {
            Text(failed.error ?? "Delivery failed")
                .foregroundStyle(.red)
                .font(.system(size: DeckTypography.bodySmall))
                .frame(maxWidth: .infinity, alignment: message.sender_type == "user" ? .trailing : .leading)
        }
    }
}
