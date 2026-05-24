import SwiftUI

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
        VStack(alignment: .leading, spacing: DeckMetrics.spacing16) {
            HStack(spacing: 0) {
                AppLogoView(size: 26)
                Spacer()
                Button {
                    isCollapsed = true
                } label: {
                    Image(systemName: "sidebar.left")
                        .font(.system(size: DeckTypography.title, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
            }
            .frame(height: 32)
            .padding(.top, DeckMetrics.spacing12)

            ScrollView {
                VStack(alignment: .leading, spacing: DeckMetrics.spacing16) {
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
        .padding(DeckMetrics.spacing12)
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
                RoundedRectangle(cornerRadius: DeckMetrics.radius8, style: .continuous)
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
        VStack(alignment: .leading, spacing: DeckMetrics.spacing8) {
            HStack(alignment: .bottom) {
                Text(title)
                    .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
                Spacer()
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .font(.system(size: DeckTypography.control, weight: .regular))
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
            HStack(spacing: DeckMetrics.channelRowGap) {
                AvatarView(channel: channel, square: isSelected && channel.type == "direct")
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.name)
                        .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .lineLimit(1)
                    Text(channel.members.first?.id ?? "session_id")
                        .font(.system(size: DeckTypography.caption, weight: .regular))
                        .foregroundStyle(DeckColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button {
                    onSettings()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: DeckTypography.body, weight: .regular))
                        .foregroundStyle(DeckColor.text)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.plain)
                .opacity(isSelected ? 1 : 0)
            }
            .padding(DeckMetrics.channelRowPadding)
            .frame(height: DeckMetrics.channelRowHeight)
            .background(isSelected || isHovering ? DeckColor.selectedRow : DeckColor.sidebar)
            .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.radius12, style: .continuous))
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
            RoundedRectangle(cornerRadius: square ? DeckMetrics.spacing6 : DeckMetrics.radius16, style: .continuous)
                .fill(DeckColor.avatar)
            if let avatarPath = channel.avatarPath,
               let image = NSImage(contentsOfFile: avatarPath) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: DeckMetrics.avatarSize, height: DeckMetrics.avatarSize)
                    .clipShape(RoundedRectangle(cornerRadius: square ? DeckMetrics.spacing6 : DeckMetrics.radius16, style: .continuous))
            } else if channel.icon != "#" && channel.icon != "●" {
                Text(channel.icon)
                    .font(.system(size: DeckTypography.body, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: DeckMetrics.avatarSize, height: DeckMetrics.avatarSize)
    }
}

struct AgentStatusView: View {
    @EnvironmentObject private var store: DeckStore

    var body: some View {
        HStack(spacing: DeckMetrics.spacing6) {
            Circle()
                .fill(DeckColor.avatar)
                .frame(width: DeckMetrics.avatarSize, height: DeckMetrics.avatarSize)
            VStack(alignment: .leading, spacing: 2) {
                Text("Mako")
                    .font(.system(size: DeckTypography.bodySmall, weight: .regular))
                    .foregroundStyle(DeckColor.text)
                Text("Online")
                    .font(.system(size: DeckTypography.caption, weight: .regular))
                    .foregroundStyle(DeckColor.muted)
            }
            Spacer(minLength: 0)
            Button {
                if let agent = store.agents.first {
                    store.settingsAgent = agent
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: DeckTypography.body, weight: .regular))
                    .foregroundStyle(DeckColor.text)
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
        }
        .padding(DeckMetrics.channelRowPadding)
        .frame(height: DeckMetrics.channelRowHeight)
        .background(DeckColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: DeckMetrics.radius12, style: .continuous))
    }
}
