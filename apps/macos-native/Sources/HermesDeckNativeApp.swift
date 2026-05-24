import SwiftUI

@main
struct HermesDeckNativeApp: App {
    @StateObject private var store = DeckStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .task {
                    await store.bootstrap()
                }
        }
        .defaultSize(width: 1024, height: 768)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Hermes Deck") {
                Button("Refresh") {
                    Task { await store.refresh() }
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
        }
    }
}
