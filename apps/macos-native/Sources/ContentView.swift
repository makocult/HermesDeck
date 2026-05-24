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
        .frame(minWidth: 800, minHeight: 600)
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
