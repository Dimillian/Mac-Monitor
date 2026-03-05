import SwiftUI

@main
struct MacMonitorApp: App {
    @State private var conversationStore = ConversationStore()
    @State private var systemStore = MacSystemStore()

    var body: some Scene {
        MenuBarExtra("MacMonitor", systemImage: "macwindow") {
            MenuBarConversationView(
                conversationStore: conversationStore,
                systemStore: systemStore
            )
            .frame(width: 460, height: 760)
            .task {
                await conversationStore.startIfNeeded()
                await systemStore.startIfNeeded()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
