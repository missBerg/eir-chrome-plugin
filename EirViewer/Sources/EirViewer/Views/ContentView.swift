import SwiftUI

enum NavTab: String, CaseIterable, Identifiable {
    case journal = "Journal"
    case chat = "Chat"
    case findCare = "Find Care"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .journal: return "doc.text"
        case .chat: return "bubble.left.and.bubble.right"
        case .findCare: return "map"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var documentVM: DocumentViewModel
    @EnvironmentObject var chatVM: ChatViewModel
    @EnvironmentObject var settingsVM: SettingsViewModel
    @EnvironmentObject var profileStore: ProfileStore
    @EnvironmentObject var chatThreadStore: ChatThreadStore

    @State private var selectedTab: NavTab = .journal
    @State private var showingAddPerson = false
    @State private var pendingFileURL: URL?

    var body: some View {
        Group {
            if profileStore.profiles.isEmpty {
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
                    case .findCare:
                        FindCareView()
                    }
                }
                .navigationSplitViewStyle(.balanced)
                .frame(minWidth: 800, minHeight: 500)
                .onAppear {
                    loadSelectedProfile()
                }
                .onChange(of: profileStore.selectedProfileID) {
                    loadSelectedProfile()
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAddPersonSheet)) { notification in
            pendingFileURL = notification.object as? URL
            showingAddPerson = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .navigateToJournalEntry)) { notification in
            if let entryID = notification.object as? String {
                documentVM.selectedEntryID = entryID
                selectedTab = .journal
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .explainEntryWithAI)) { notification in
            guard let entry = notification.object as? EirEntry,
                  let profileID = profileStore.selectedProfileID else { return }
            chatVM.newConversation(chatThreadStore: chatThreadStore, profileID: profileID)
            selectedTab = .chat

            var prompt = "Explain this journal entry. Help me understand what happened during this visit, what the medical terms mean, and if there's anything important I should be aware of:\n\n"
            prompt += "Date: \(entry.date ?? "Unknown")\n"
            prompt += "Category: \(entry.category ?? "Unknown")\n"
            if let summary = entry.content?.summary { prompt += "Summary: \(summary)\n" }
            if let details = entry.content?.details { prompt += "Details: \(details)\n" }
            if let notes = entry.content?.notes, !notes.isEmpty {
                prompt += "Notes: \(notes.joined(separator: "\n"))\n"
            }

            chatVM.inputText = prompt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                chatVM.sendMessage(
                    document: documentVM.document,
                    settingsVM: settingsVM,
                    chatThreadStore: chatThreadStore,
                    profileID: profileID
                )
            }
        }
        .sheet(isPresented: $showingAddPerson) {
            AddPersonSheet(initialURL: pendingFileURL)
        }
    }

    private func loadSelectedProfile() {
        guard let profile = profileStore.selectedProfile else { return }
        documentVM.loadFile(url: profile.fileURL)
        chatThreadStore.loadThreads(for: profile.id)
    }
}
