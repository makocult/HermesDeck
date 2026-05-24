import SwiftUI

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

            HStack(alignment: .center, spacing: 12) {
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
                    .frame(height: 20)
                }
                .frame(height: 20, alignment: .leading)
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
            .frame(height: 44)
            .background(DeckColor.composer)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(height: store.isSlashMenuOpen || store.draft.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/") ? nil : 68)
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

    // AppKit bridge: NSTextView gives stable keyboard semantics and avoids the
    // SwiftUI TextField resizing behavior that distorted the composer.
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
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
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 20)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: 20)
        textView.textContainer?.widthTracksTextView = true
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
