import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case journal = "Journal"
    case chat = "Chat"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .journal: return "doc.text"
        case .chat: return "bubble.left.and.bubble.right"
        case .settings: return "gearshape"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel

    @State private var selectedTab: NavTab = .journal

    var body: some View {
        if documentVM.document == nil {
            WelcomeView()
        } else {
            NavigationSplitView {
                SidebarView(selectedTab: $selectedTab)
            } detail: {
                switch selectedTab {
                case .journal:
                    JournalTimelineView()
                case .chat:
                    ChatView()
                case .settings:
                    InlineSettingsView()
                }
            }
            .navigationSplitViewStyle(.balanced)
            .frame(minWidth: 800, minHeight: 500)
        }
    }
}
