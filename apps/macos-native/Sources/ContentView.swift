import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: DeckStore
    @State private var isSidebarCollapsed = false

    var body: some View {
        HStack(spacing: 0) {
            if !isSidebarCollapsed {
                SidebarView(isCollapsed: $isSidebarCollapsed)
                    .frame(width: 200)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            ChatView(isSidebarCollapsed: $isSidebarCollapsed)
        }
        .frame(minWidth: 1024, minHeight: 768)
        .background(DeckColor.surface)
        .ignoresSafeArea(.container, edges: .top)
        .animation(.easeInOut(duration: 0.18), value: isSidebarCollapsed)
        .sheet(isPresented: $store.isCreatingChannel) {
            CreateChannelView()
                .frame(width: 420, height: 420)
        }
        .sheet(isPresented: $store.isAddingAgent) {
            AddAgentView()
                .frame(width: 440, height: 430)
        }
        .sheet(item: $store.editingChannel) { channel in
            ChannelSettingsView(channel: channel)
                .frame(width: 460, height: 520)
        }
        .sheet(item: $store.settingsAgent) { agent in
            AgentSettingsView(agent: agent)
                .frame(minWidth: 820, minHeight: 620)
        }
        .alert("Hermes Deck", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: DeckStore
    @Binding var isCollapsed: Bool

    var directChannels: [Channel] {
        store.channels.filter { $0.type == "direct" }
    }

    var normalChannels: [Channel] {
        store.channels.filter { $0.type == "channel" }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                AppLogoView(size: 26)
                Spacer()
                Button {
                    isCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)
            .padding(.top, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SidebarSection(title: "Direct", onAdd: { store.isAddingAgent = true }) {
                        ForEach(directChannels) { channel in
                            ChannelRow(
                                channel: channel,
                                isSelected: channel.id == store.selectedChannelId,
                                onSelect: { store.select(channel: channel) },
                                onSettings: { store.editingChannel = channel }
                            )
                        }
                    }

                    Rectangle()
                        .fill(DeckColor.border)
                        .frame(height: 1)

                    SidebarSection(title: "Channels", onAdd: { store.isCreatingChannel = true }) {
                        ForEach(normalChannels) { channel in
                            ChannelRow(
                                channel: channel,
                                isSelected: channel.id == store.selectedChannelId,
                                onSelect: { store.select(channel: channel) },
                                onSettings: { store.editingChannel = channel }
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: .infinity)

            AgentStatusView()
                .padding(.top, 0)
        }
        .padding(12)
        .background(DeckColor.sidebar)
    }
}

struct AppLogoView: View {
    let size: CGFloat

    var body: some View {
        Group {
            if let url = Bundle.module.url(forResource: "HermesDeckLogo", withExtension: "png"),
               let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(red: 13 / 255, green: 158 / 255, blue: 224 / 255))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

struct SidebarSection<Content: View>: View {
    let title: String
    let onAdd: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .bottom) {
                Text(title)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
            }
            content
        }
    }
}

struct ChannelRow: View {
    let channel: Channel
    let isSelected: Bool
    let onSelect: () -> Void
    let onSettings: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                AvatarView(channel: channel, square: isSelected && channel.type == "direct")
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .lineLimit(1)
                    Text(channel.members.first?.id ?? "session_id")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1 : 0)
            }
            .padding(6)
            .frame(height: 44)
            .background(isSelected || isHovering ? DeckColor.selectedRow : DeckColor.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
    }
}

struct AvatarView: View {
    let channel: Channel
    var square = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: square ? 6 : 16, style: .continuous)
                .fill(DeckColor.avatar)
            if let avatarPath = channel.avatarPath,
               let image = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: square ? 6 : 16, style: .continuous))
            } else if channel.icon != "#" && channel.icon != "●" {
                Text(channel.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 32, height: 32)
    }
}

struct AgentStatusView: View {
    @EnvironmentObject private var store: DeckStore

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(DeckColor.avatar)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mako")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(DeckColor.text)
                Text("Online")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
            }
            Spacer(minLength: 0)
            Button {
                if let agent = store.agents.first {
                    store.settingsAgent = agent
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(DeckColor.text)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(6)
        .frame(height: 44)
        .background(DeckColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

enum DeckColor {
    static let sidebar = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1) : NSColor(red: 250 / 255, green: 250 / 255, blue: 254 / 255, alpha: 1)
    })
    static let selectedRow = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.20, green: 0.20, blue: 0.23, alpha: 1) : NSColor(red: 232 / 255, green: 234 / 255, blue: 238 / 255, alpha: 1)
    })
    static let surface = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.13, green: 0.13, blue: 0.15, alpha: 1) : NSColor.white
    })
    static let composer = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.17, green: 0.17, blue: 0.19, alpha: 1) : NSColor(red: 250 / 255, green: 250 / 255, blue: 254 / 255, alpha: 1)
    })
    static let border = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.29, green: 0.29, blue: 0.32, alpha: 1) : NSColor(red: 224 / 255, green: 224 / 255, blue: 224 / 255, alpha: 1)
    })
    static let text = Color(nsColor: NSColor.labelColor)
    static let headerText = Color(nsColor: NSColor.labelColor)
    static let muted = Color(nsColor: NSColor.secondaryLabelColor)
    static let placeholder = Color(nsColor: NSColor.placeholderTextColor)
    static let avatar = Color(red: 133 / 255, green: 133 / 255, blue: 125 / 255)
    static let online = Color(red: 48 / 255, green: 214 / 255, blue: 105 / 255)
    static let tableHeader = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.18, green: 0.18, blue: 0.21, alpha: 1) : NSColor(red: 246 / 255, green: 247 / 255, blue: 250 / 255, alpha: 1)
    })
    static let codeHeader = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.15, green: 0.15, blue: 0.17, alpha: 1) : NSColor(red: 242 / 255, green: 244 / 255, blue: 247 / 255, alpha: 1)
    })
    static let codeBackground = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.11, green: 0.11, blue: 0.13, alpha: 1) : NSColor(red: 250 / 255, green: 251 / 255, blue: 253 / 255, alpha: 1)
    })
    static let codeKeyword = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.55, green: 0.70, blue: 1.00, alpha: 1) : NSColor(red: 0.20, green: 0.34, blue: 0.78, alpha: 1)
    })
    static let codeString = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.78, green: 0.66, blue: 0.44, alpha: 1) : NSColor(red: 0.57, green: 0.32, blue: 0.04, alpha: 1)
    })
    static let codeNumber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.73, green: 0.58, blue: 0.94, alpha: 1) : NSColor(red: 0.45, green: 0.25, blue: 0.74, alpha: 1)
    })
    static let codeComment = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.isDarkMode ? NSColor(red: 0.45, green: 0.55, blue: 0.49, alpha: 1) : NSColor(red: 0.36, green: 0.49, blue: 0.40, alpha: 1)
    })
}

private extension NSAppearance {
    var isDarkMode: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

struct AgentSettingsView: View {
    let agent: Agent
    @StateObject private var config = HermesConfigStore()
    @State private var tab = "provider"

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(agent.name) Settings")
                        .font(.title2)
                        .bold()
                    Text(agent.host_label ?? agent.device_type)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !config.status.isEmpty {
                    Text(config.status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()

            Picker("Settings", selection: $tab) {
                Text("Provider").tag("provider")
                Text("Cron").tag("cron")
                Text("SOUL.md").tag("soul")
                Text("USER.md").tag("user")
                Text("Skills").tag("skills")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            Divider()

            switch tab {
            case "provider":
                EditorPane(
                    title: "~/.hermes/config.yaml",
                    text: $config.configText,
                    saveTitle: "Save Provider Config",
                    onSave: config.saveConfig
                )
            case "cron":
                EditorPane(
                    title: "~/.hermes/cron/jobs.json",
                    text: $config.cronText,
                    saveTitle: "Save Cron",
                    onSave: config.saveCron
                )
            case "soul":
                EditorPane(
                    title: "~/.hermes/SOUL.md",
                    text: $config.soulText,
                    saveTitle: "Save SOUL.md",
                    onSave: config.saveSoul
                )
            case "user":
                EditorPane(
                    title: "~/.hermes/memories/USER.md",
                    text: $config.userText,
                    saveTitle: "Save USER.md",
                    onSave: config.saveUser
                )
            default:
                SkillSettingsView(config: config)
            }
        }
        .onAppear {
            config.load()
        }
    }
}

struct EditorPane: View {
    let title: String
    @Binding var text: String
    let saveTitle: String
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(saveTitle, action: onSave)
                    .keyboardShortcut("s", modifiers: [.command])
            }
            TextEditor(text: $text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.2))
                }
        }
        .padding()
    }
}

struct SkillSettingsView: View {
    @ObservedObject var config: HermesConfigStore

    var body: some View {
        HSplitView {
            List(selection: Binding(
                get: { config.selectedSkill?.id },
                set: { id in
                    config.selectedSkill = config.skills.first { $0.id == id }
                    config.loadSelectedSkill()
                }
            )) {
                ForEach(config.skills) { skill in
                    VStack(alignment: .leading) {
                        Text(skill.name)
                        Text(skill.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(skill.id)
                }
            }
            .frame(minWidth: 220)

            EditorPane(
                title: config.selectedSkill.map { "~/.hermes/skills/\($0.id)/SKILL.md" } ?? "No skill selected",
                text: $config.selectedSkillText,
                saveTitle: "Save Skill",
                onSave: config.saveSelectedSkill
            )
        }
        .padding(.top, 8)
    }
}

struct ChatView: View {
    @EnvironmentObject private var store: DeckStore
    @Binding var isSidebarCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            ChatHeader(isSidebarCollapsed: $isSidebarCollapsed)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(store.selectedMessages) { message in
                            MessageView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .onChange(of: store.selectedMessages.count) { _, _ in
                    if let last = store.selectedMessages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            ComposerView()
        }
        .background(DeckColor.surface)
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
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            Text(store.selectedChannel?.name ?? "No Channel")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DeckColor.headerText)
            Spacer()
            Button {
                Task { await store.refresh() }
            } label: {
                Image(systemName: "cellularbars")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(signalColor)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help(memberStatus == "online" ? "Agent online" : "Agent offline")
        }
        .frame(height: 56)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 24)
        .padding(.top, 0)
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

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            MessageAvatar()
            VStack(alignment: .leading, spacing: 4) {
                MessageHeader(senderName: senderName, createdAt: message.created_at)
                if let activity = store.activitiesByMessage[message.id] {
                    AgentActivityView(activity: activity)
                } else if message.isStreaming {
                    AgentTypingView()
                }
                MarkdownBody(content: message.isStreaming ? "_Streaming..._" : message.content, baseFontSize: 13)
                MessageFailureView(message: message)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AgentTypingView: View {
    var body: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.55)
            Text("输入中...")
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DeckColor.muted)
        }
    }
}

struct AgentActivityView: View {
    let activity: AgentActivity

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(activity.isActive ? DeckColor.online : DeckColor.muted)
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DeckColor.text)
                if !activity.text.isEmpty {
                    Text(activity.text)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(DeckColor.composer)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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
        HStack(alignment: .top, spacing: 6) {
            Spacer(minLength: 80)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    Text(message.created_at.formattedMessageTime())
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                }
                MarkdownBody(content: message.content, fillsWidth: false)
                    .frame(maxWidth: 560, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(DeckColor.selectedRow)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
        HStack(spacing: 24) {
            Text(senderName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DeckColor.text)
            Text(createdAt.formattedMessageTime())
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(DeckColor.muted)
            Spacer(minLength: 0)
        }
    }
}

struct MessageAvatar: View {
    var body: some View {
        Circle()
            .fill(DeckColor.avatar)
            .frame(width: 32, height: 32)
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
                .font(.system(size: 12))
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
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: message.sender_type == "user" ? .trailing : .leading)
        }
    }
}

struct MarkdownBody: View {
    let content: String
    var baseFontSize: CGFloat = 12
    var fillsWidth = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(MarkdownParser.blocks(from: content).enumerated()), id: \.offset) { _, block in
                MarkdownBlockView(block: block, baseFontSize: baseFontSize)
            }
        }
        .frame(maxWidth: fillsWidth ? .infinity : nil, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
}

struct MarkdownBlockView: View {
    let block: MarkdownBlock
    let baseFontSize: CGFloat

    var body: some View {
        switch block {
        case let .heading(level, text):
            Text(inlineMarkdown(text))
                .font(.system(size: baseFontSize + (level == 1 ? 4 : 2), weight: .semibold))
                .foregroundStyle(DeckColor.text)
                .padding(.top, level == 1 ? 4 : 2)
                .textSelection(.enabled)
        case let .paragraph(text):
            Text(inlineMarkdown(text))
                .font(.system(size: baseFontSize, weight: .regular))
                .foregroundStyle(DeckColor.text)
                .lineSpacing(4)
                .textSelection(.enabled)
        case let .quote(text):
            HStack(alignment: .top, spacing: 8) {
                Rectangle()
                    .fill(DeckColor.border)
                    .frame(width: 3)
                Text(inlineMarkdown(text))
                    .font(.system(size: baseFontSize, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
        case let .list(items, ordered, checked):
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(marker(index: index, ordered: ordered, checked: checked[index]))
                            .font(.system(size: baseFontSize, weight: .regular))
                            .foregroundStyle(DeckColor.muted)
                            .frame(width: ordered ? 24 : 16, alignment: .trailing)
                        Text(inlineMarkdown(item))
                            .font(.system(size: baseFontSize, weight: .regular))
                            .foregroundStyle(DeckColor.text)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                }
            }
        case let .code(language, code):
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    if !language.isEmpty {
                        Text(language)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DeckColor.muted)
                    }
                    Spacer()
                    CopyMessageButton(content: code)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(DeckColor.codeHeader)
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(highlightedCode(code, language: language))
                        .font(.system(size: baseFontSize, weight: .regular, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(12)
                }
            }
            .background(DeckColor.codeBackground)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DeckColor.border, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        case let .table(rows):
            ScrollView(.horizontal, showsIndicators: false) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    ForEach(Array(normalizedRows(rows).enumerated()), id: \.offset) { rowIndex, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                tableCell(cell, isHeader: rowIndex == 0)
                            }
                        }
                    }
                }
                .background(DeckColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DeckColor.border, lineWidth: 1)
                }
            }
        case .separator:
            Rectangle()
                .fill(DeckColor.border)
                .frame(height: 1)
                .padding(.vertical, 4)
        }
    }

    private func tableCell(_ cell: String, isHeader: Bool) -> some View {
        ZStack(alignment: .leading) {
            (isHeader ? DeckColor.tableHeader : Color.clear)
            Text(inlineMarkdown(cell))
                .font(.system(size: baseFontSize, weight: isHeader ? .semibold : .regular))
                .foregroundStyle(isHeader ? DeckColor.headerText : DeckColor.text)
                .lineLimit(nil)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(minWidth: 120, maxWidth: 260, alignment: .leading)
        }
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(DeckColor.border)
                .frame(width: 0.5)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DeckColor.border)
                .frame(height: 0.5)
        }
    }

    private func normalizedRows(_ rows: [[String]]) -> [[String]] {
        let width = rows.map(\.count).max() ?? 0
        return rows.map { row in
            if row.count >= width { return row }
            return row + Array(repeating: "", count: width - row.count)
        }
    }

    private func highlightedCode(_ code: String, language: String) -> AttributedString {
        var result = AttributedString()
        let keywords = syntaxKeywords(language: language)
        let lines = code.components(separatedBy: "\n")
        for (lineIndex, line) in lines.enumerated() {
            result += highlightedLine(line, keywords: keywords)
            if lineIndex < lines.count - 1 {
                result += AttributedString("\n")
            }
        }
        return result
    }

    private func highlightedLine(_ line: String, keywords: Set<String>) -> AttributedString {
        let commentStart = findCommentStart(in: line)
        let codePart = commentStart.map { String(line[..<$0]) } ?? line
        let commentPart = commentStart.map { String(line[$0...]) }
        var output = highlightCodePart(codePart, keywords: keywords)
        if let commentPart {
            var comment = AttributedString(commentPart)
            comment.foregroundColor = DeckColor.codeComment
            output += comment
        }
        return output
    }

    private func highlightCodePart(_ line: String, keywords: Set<String>) -> AttributedString {
        var output = AttributedString()
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" || char == "'" {
                let end = scanStringEnd(in: line, from: index, quote: char)
                var token = AttributedString(String(line[index...end]))
                token.foregroundColor = DeckColor.codeString
                output += token
                index = line.index(after: end)
            } else if char.isNumber {
                let end = line[index...].firstIndex { !$0.isNumber && $0 != "." } ?? line.endIndex
                var token = AttributedString(String(line[index..<end]))
                token.foregroundColor = DeckColor.codeNumber
                output += token
                index = end
            } else if char.isLetter || char == "_" {
                let end = line[index...].firstIndex { !$0.isLetter && !$0.isNumber && $0 != "_" } ?? line.endIndex
                let word = String(line[index..<end])
                var token = AttributedString(word)
                token.foregroundColor = keywords.contains(word) ? DeckColor.codeKeyword : DeckColor.text
                output += token
                index = end
            } else {
                var token = AttributedString(String(char))
                token.foregroundColor = DeckColor.text
                output += token
                index = line.index(after: index)
            }
        }
        return output
    }

    private func findCommentStart(in line: String) -> String.Index? {
        if let swift = line.range(of: "//")?.lowerBound {
            return swift
        }
        return line.range(of: "#")?.lowerBound
    }

    private func scanStringEnd(in line: String, from start: String.Index, quote: Character) -> String.Index {
        var index = line.index(after: start)
        var escaped = false
        while index < line.endIndex {
            let char = line[index]
            if char == quote && !escaped {
                return index
            }
            escaped = char == "\\" && !escaped
            if char != "\\" { escaped = false }
            index = line.index(after: index)
        }
        return line.index(before: line.endIndex)
    }

    private func syntaxKeywords(language: String) -> Set<String> {
        let common: Set<String> = [
            "as", "async", "await", "break", "case", "catch", "class", "const", "continue",
            "default", "do", "else", "enum", "export", "false", "for", "from", "func",
            "function", "guard", "if", "import", "in", "let", "nil", "null", "private",
            "public", "return", "static", "struct", "switch", "throw", "throws", "true",
            "try", "type", "var", "while"
        ]
        if language.lowercased().contains("sql") {
            return common.union(["select", "from", "where", "insert", "update", "delete", "join", "left", "right", "group", "order", "by", "limit"])
        }
        return common
    }

    private func marker(index: Int, ordered: Bool, checked: Bool?) -> String {
        if let checked {
            return checked ? "☑" : "☐"
        }
        return ordered ? "\(index + 1)." : "•"
    }

    private func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let parsed = try? AttributedString(markdown: text, options: options) {
            return parsed
        }
        return AttributedString(text)
    }
}

enum MarkdownBlock {
    case heading(level: Int, text: String)
    case paragraph(String)
    case quote(String)
    case list(items: [String], ordered: Bool, checked: [Bool?])
    case code(language: String, code: String)
    case table([[String]])
    case separator
}

enum MarkdownParser {
    static func blocks(from content: String) -> [MarkdownBlock] {
        let lines = content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var listItems: [String] = []
        var listChecks: [Bool?] = []
        var listOrdered = false
        var inCode = false
        var codeLanguage = ""
        var codeLines: [String] = []

        func flushParagraph() {
            let text = paragraph.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            paragraph.removeAll()
        }

        func flushList() {
            if !listItems.isEmpty {
                blocks.append(.list(items: listItems, ordered: listOrdered, checked: listChecks))
            }
            listItems.removeAll()
            listChecks.removeAll()
            listOrdered = false
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if inCode {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
                    inCode = false
                    codeLanguage = ""
                    codeLines.removeAll()
                } else {
                    codeLines.append(line)
                }
                continue
            }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                flushList()
                inCode = true
                codeLanguage = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if trimmed == "---" || trimmed == "⸻" {
                flushParagraph()
                flushList()
                blocks.append(.separator)
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                flushList()
                blocks.append(.heading(level: heading.level, text: heading.text))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushList()
                blocks.append(.quote(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)))
                continue
            }

            if let item = parseListItem(trimmed) {
                flushParagraph()
                if listItems.isEmpty {
                    listOrdered = item.ordered
                } else if listOrdered != item.ordered {
                    flushList()
                    listOrdered = item.ordered
                }
                listItems.append(item.text)
                listChecks.append(item.checked)
                continue
            }

            if isTableLine(trimmed) {
                flushParagraph()
                flushList()
                let row = parseTableRow(trimmed)
                if !row.isEmpty {
                    blocks.append(.table([row]))
                }
                continue
            }

            flushList()
            paragraph.append(line)
        }

        if inCode {
            blocks.append(.code(language: codeLanguage, code: codeLines.joined(separator: "\n")))
        }
        flushParagraph()
        flushList()
        return mergeTables(blocks)
    }

    private static func parseHeading(_ line: String) -> (level: Int, text: String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
        return (hashes, String(line.dropFirst(hashes + 1)))
    }

    private static func parseListItem(_ line: String) -> (ordered: Bool, checked: Bool?, text: String)? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            let raw = String(line.dropFirst(marker.count))
            let parsed = parseTask(raw)
            return (false, parsed.checked, parsed.text)
        }
        guard let dot = line.firstIndex(of: ".") else { return nil }
        let prefix = line[..<dot]
        guard !prefix.isEmpty, prefix.allSatisfy(\.isNumber) else { return nil }
        let after = line[line.index(after: dot)...]
        guard after.first == " " else { return nil }
        return (true, nil, String(after.dropFirst()))
    }

    private static func parseTask(_ value: String) -> (checked: Bool?, text: String) {
        if value.hasPrefix("[x] ") || value.hasPrefix("[X] ") {
            return (true, String(value.dropFirst(4)))
        }
        if value.hasPrefix("[ ] ") {
            return (false, String(value.dropFirst(4)))
        }
        return (nil, value)
    }

    private static func isTableLine(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.contains("|")
    }

    private static func parseTableRow(_ line: String) -> [String] {
        line
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ row: [String]) -> Bool {
        !row.isEmpty && row.allSatisfy { cell in
            let clean = cell.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return clean.trimmingCharacters(in: .whitespaces).isEmpty && cell.contains("-")
        }
    }

    private static func mergeTables(_ blocks: [MarkdownBlock]) -> [MarkdownBlock] {
        var merged: [MarkdownBlock] = []
        var pendingRows: [[String]] = []
        for block in blocks {
            if case let .table(rows) = block {
                pendingRows.append(contentsOf: rows)
                continue
            }
            flushRows(&pendingRows, into: &merged)
            merged.append(block)
        }
        flushRows(&pendingRows, into: &merged)
        return merged
    }

    private static func flushRows(_ rows: inout [[String]], into blocks: inout [MarkdownBlock]) {
        guard !rows.isEmpty else { return }
        let filtered = rows.filter { !isTableSeparator($0) }
        if !filtered.isEmpty {
            blocks.append(.table(filtered))
        }
        rows.removeAll()
    }
}

struct ComposerView: View {
    @EnvironmentObject private var store: DeckStore
    @FocusState private var isFocused: Bool

    private var filteredCommands: [SlashCommand] {
        let trimmed = store.draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = trimmed.hasPrefix("/") ? trimmed.lowercased() : ""
        guard !query.isEmpty else { return store.slashCommands }
        return store.slashCommands.filter {
            $0.name.lowercased().contains(query) || $0.description.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if store.isSlashMenuOpen || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") {
                SlashCommandMenu(commands: filteredCommands) { command in
                    store.draft = "\(command.name) "
                    store.isSlashMenuOpen = false
                }
                .frame(maxWidth: 420)
            }

            HStack(spacing: 12) {
                Button {
                    store.isSlashMenuOpen.toggle()
                    Task { await store.loadSlashCommands() }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                ZStack(alignment: .leading) {
                    if store.draft.isEmpty {
                        Text("placeholder")
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(DeckColor.placeholder)
                            .frame(width: 78, height: 17, alignment: .leading)
                    }
                    ComposerTextView(text: $store.draft) {
                        Task { await store.sendDraft() }
                    } onSlashChanged: { isOpen in
                        store.isSlashMenuOpen = isOpen
                        if isOpen {
                            Task { await store.loadSlashCommands() }
                        }
                    }
                    .focused($isFocused)
                    .frame(minHeight: 20, maxHeight: 92)
                }
                .frame(minHeight: 20, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    Task { await store.sendDraft() }
                } label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DeckColor.muted)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .background(DeckColor.composer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(DeckColor.surface)
    }
}

struct SlashCommandMenu: View {
    let commands: [SlashCommand]
    let onSelect: (SlashCommand) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(commands.prefix(8)) { command in
                Button {
                    onSelect(command)
                } label: {
                    HStack(spacing: 10) {
                        Text(command.name)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(DeckColor.text)
                            .frame(width: 118, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(command.description.isEmpty ? command.category : command.description)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(DeckColor.muted)
                                .lineLimit(1)
                            Text(command.category)
                                .font(.system(size: 10, weight: .regular))
                                .foregroundStyle(DeckColor.placeholder)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(DeckColor.surface)
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DeckColor.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 14, x: 0, y: 8)
    }
}

struct ComposerTextView: NSViewRepresentable {
    @Binding var text: String
    let onSend: () -> Void
    let onSlashChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        let textView = ComposerNSTextView()
        textView.delegate = context.coordinator
        textView.onSend = onSend
        textView.font = .systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = .zero
        textView.textContainer?.lineFragmentPadding = 0
        textView.minSize = NSSize(width: 0, height: 20)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 92)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
        }
        textView.textColor = NSColor.labelColor
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ComposerTextView

        init(_ parent: ComposerTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            parent.onSlashChanged(textView.string.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/"))
        }
    }
}

final class ComposerNSTextView: NSTextView {
    var onSend: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 && !event.modifierFlags.contains(.shift) {
            onSend?()
            return
        }
        super.keyDown(with: event)
    }
}

extension String {
    func formattedMessageTime() -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: self) else { return "" }
        let output = DateFormatter()
        output.dateFormat = "h:mm a"
        return output.string(from: date).lowercased()
    }
}

struct CreateChannelView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var routingMode = "manual"
    @State private var selectedAgentIds: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Create Channel")
                    .font(.title2)
                    .bold()
                Spacer()
            }

            TextField("Channel name", text: $name)
                .textFieldStyle(.roundedBorder)

            Picker("Routing", selection: $routingMode) {
                Text("manual").tag("manual")
                Text("single").tag("single")
                Text("broadcast").tag("broadcast")
            }
            .pickerStyle(.segmented)

            Text("Members")
                .font(.headline)
            ForEach(store.agents) { agent in
                Toggle(agent.name, isOn: Binding(
                    get: { selectedAgentIds.contains(agent.id) },
                    set: { value in
                        if value { selectedAgentIds.insert(agent.id) }
                        else { selectedAgentIds.remove(agent.id) }
                    }
                ))
            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button("Create") {
                    Task {
                        await store.createChannel(
                            name: name,
                            selectedAgentIds: Array(selectedAgentIds),
                            routingMode: routingMode
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            selectedAgentIds = Set(store.agents.prefix(1).map(\.id))
        }
    }
}

struct AddAgentView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = "Mac Hermes"
    @State private var avatarPath: String?
    @State private var host = "127.0.0.1"
    @State private var port = ""
    @State private var isTesting = false
    @State private var isConnectionValid = false
    @State private var didAutoDetect = false
    @State private var isChoosingAvatar = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Add Agent")
                    .font(.title2)
                    .bold()
                Text("Detect the local Hermes install, or enter an HTTP endpoint.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(DeckColor.text)

            HStack(alignment: .top, spacing: 12) {
                avatarPreview
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.plain)
                        .foregroundStyle(DeckColor.text)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(fieldBackground)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Service")
                    .font(.system(size: 12))
                    .foregroundStyle(DeckColor.muted)
                HStack(spacing: 8) {
                    TextField("IP address or host", text: $host)
                        .textFieldStyle(.plain)
                        .foregroundStyle(DeckColor.text)
                        .padding(.horizontal, 10)
                        .frame(height: 34)
                        .background(fieldBackground)
                    TextField("Port", text: $port)
                        .textFieldStyle(.plain)
                        .foregroundStyle(DeckColor.text)
                        .padding(.horizontal, 10)
                        .frame(width: 90, height: 34)
                        .background(fieldBackground)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(isConnectionValid ? DeckColor.online : Color.orange)
                    .frame(width: 8, height: 8)
                Text(statusHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
            }

            HStack {
                Button(isTesting ? "Detecting..." : "Detect Local Hermes") {
                    Task {
                        isTesting = true
                        await store.localHermes.discover()
                        host = store.localHermes.probe.host
                        port = "\(store.localHermes.probe.port)"
                        isConnectionValid = store.localHermes.probe.isReachable
                        didAutoDetect = true
                        isTesting = false
                    }
                }
                .disabled(isTesting)
                Button("Test Connection") {
                    Task {
                        isTesting = true
                        isConnectionValid = await store.localHermes.test(
                            host: host,
                            port: Int(port.trimmingCharacters(in: .whitespacesAndNewlines))
                        )
                        isTesting = false
                    }
                }
                .disabled(isTesting)
                Spacer()
            }

            Spacer()
            HStack {
                Button("Cancel") { dismiss() }
                    .foregroundStyle(DeckColor.text)
                Spacer()
                Button("Add Agent") {
                    Task {
                        await store.createAgent(
                            name: name,
                            hostLabel: Host.current().localizedName ?? "Local Mac",
                            deviceType: "macbook",
                            capabilities: [
                                "local_hermes_gateway",
                                store.localHermes.probe.connectionKind,
                                "gateway_endpoint:\(store.localHermes.probe.endpoint)"
                            ],
                            defaultModel: "hermes",
                            defaultProvider: "local-hermes",
                            endpoint: store.localHermes.probe.endpoint,
                            connectionKind: store.localHermes.probe.connectionKind,
                            icon: effectiveIcon,
                            avatarPath: avatarPath
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !isConnectionValid)
            }
        }
        .padding(20)
        .background(DeckColor.surface)
        .fileImporter(isPresented: $isChoosingAvatar, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                avatarPath = copyAvatar(url)
            }
        }
        .task {
            await store.localHermes.discover()
            host = store.localHermes.probe.host
            port = "\(store.localHermes.probe.port)"
            isConnectionValid = store.localHermes.probe.isReachable
            didAutoDetect = true
        }
    }

    private var effectiveIcon: String {
        return String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    private var statusHint: String {
        if isConnectionValid { return store.localHermes.probe.statusText }
        if didAutoDetect { return store.localHermes.probe.statusText }
        return "Detect local Hermes or enter an address, then test."
    }

    private var fieldBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(DeckColor.composer)
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DeckColor.border, lineWidth: 1)
            }
    }

    private var avatarPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DeckColor.avatar)
            if let avatarPath, let image = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                Text(effectiveIcon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 56, height: 56)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            isChoosingAvatar = true
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(DeckColor.surface)
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(DeckColor.text)
            }
            .frame(width: 20, height: 20)
        }
    }

    private func copyAvatar(_ url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Hermes Deck/Avatars", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let destination = dir.appending(path: "\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }
}

struct ChannelSettingsView: View {
    @EnvironmentObject private var store: DeckStore
    @Environment(\.dismiss) private var dismiss
    let channel: Channel

    @State private var name: String
    @State private var icon: String
    @State private var avatarPath: String?
    @State private var isChoosingAvatar = false
    @State private var routingMode: String
    @State private var selectedAgentIds: Set<String>

    init(channel: Channel) {
        self.channel = channel
        _name = State(initialValue: channel.name)
        _icon = State(initialValue: channel.icon)
        _avatarPath = State(initialValue: channel.avatarPath)
        _routingMode = State(initialValue: channel.routing_mode)
        _selectedAgentIds = State(initialValue: Set(channel.members.map(\.id)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(channel.type == "direct" ? "Direct Settings" : "Channel Settings")
                .font(.title2)
                .bold()

            HStack(alignment: .top, spacing: 12) {
                settingsAvatarPreview
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                    TextField("Avatar / Icon", text: $icon)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Picker("Routing", selection: $routingMode) {
                Text("single").tag("single")
                Text("manual").tag("manual")
                Text("broadcast").tag("broadcast")
            }
            .pickerStyle(.segmented)
            .disabled(channel.type == "direct")

            Text("Agents")
                .font(.headline)
            ForEach(store.agents) { agent in
                Toggle(agent.name, isOn: Binding(
                    get: { selectedAgentIds.contains(agent.id) },
                    set: { value in
                        if channel.type == "direct" {
                            selectedAgentIds = value ? [agent.id] : []
                        } else if value {
                            selectedAgentIds.insert(agent.id)
                        } else {
                            selectedAgentIds.remove(agent.id)
                        }
                    }
                ))
                .disabled(channel.type == "direct" && !selectedAgentIds.contains(agent.id))
            }

            Spacer()

            HStack {
                if channel.type == "direct", let agent = channel.members.first {
                    Button(role: .destructive) {
                        Task {
                            await store.deleteAgent(agent)
                            dismiss()
                        }
                    } label: {
                        Text("Remove Direct")
                    }
                } else if channel.type == "channel" {
                    Button(role: .destructive) {
                        Task {
                            await store.deleteChannel(channel)
                            dismiss()
                        }
                    } label: {
                        Text("Delete Channel")
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    Task {
                        await store.updateChannel(
                            channel,
                            name: name,
                            icon: icon,
                            routingMode: channel.type == "direct" ? "single" : routingMode,
                            memberIds: Array(selectedAgentIds),
                            avatarPath: avatarPath
                        )
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAgentIds.isEmpty)
            }
        }
        .padding(20)
        .fileImporter(isPresented: $isChoosingAvatar, allowedContentTypes: [.image]) { result in
            if case let .success(url) = result {
                avatarPath = copyAvatar(url)
            }
        }
    }

    private var settingsAvatarPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(DeckColor.avatar)
            if let avatarPath, let image = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                Text(String(icon.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 48, height: 48)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            isChoosingAvatar = true
        }
        .overlay(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(DeckColor.surface)
                Image(systemName: "camera.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DeckColor.text)
            }
            .frame(width: 18, height: 18)
        }
    }

    private func copyAvatar(_ url: URL) -> String? {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }
        do {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appending(path: "Hermes Deck/Avatars", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let ext = url.pathExtension.isEmpty ? "png" : url.pathExtension
            let destination = dir.appending(path: "\(UUID().uuidString).\(ext)")
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: url, to: destination)
            return destination.path
        } catch {
            return nil
        }
    }
}
