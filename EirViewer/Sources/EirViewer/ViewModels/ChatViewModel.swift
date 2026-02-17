import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    private var streamingTask: Task<Void, Never>?

    func sendMessage(
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        chatThreadStore: ChatThreadStore,
        profileID: UUID
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        // Auto-create thread if none selected
        if chatThreadStore.selectedThreadID == nil {
            chatThreadStore.createThread(profileID: profileID)
        }

        let userMessage = ChatMessage(role: .user, content: text)
        chatThreadStore.addMessage(userMessage)
        inputText = ""

        guard let config = settingsVM.activeProvider else {
            errorMessage = "No LLM provider selected. Configure one in Settings."
            return
        }

        let apiKey = settingsVM.apiKey(for: config.type)
        guard !apiKey.isEmpty else {
            errorMessage = "No API key set for \(config.type.rawValue). Add one in Settings."
            return
        }

        isStreaming = true
        errorMessage = nil

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        chatThreadStore.addMessage(assistantMessage)
        let assistantIndex = chatThreadStore.messages.count - 1

        let systemPrompt = SystemPrompt.build(from: document)
        var llmMessages: [(role: String, content: String)] = [
            (role: "system", content: systemPrompt)
        ]
        for msg in chatThreadStore.messages.dropLast() {
            switch msg.role {
            case .user: llmMessages.append((role: "user", content: msg.content))
            case .assistant: llmMessages.append((role: "assistant", content: msg.content))
            case .system: break
            }
        }

        let service = LLMService(config: config, apiKey: apiKey)
        let capturedMessages = llmMessages
        let isNewThread = chatThreadStore.messages.count == 2
        let threadID = chatThreadStore.selectedThreadID

        streamingTask = Task {
            do {
                try await service.streamChat(messages: capturedMessages) { [weak chatThreadStore] token in
                    Task { @MainActor in
                        guard let store = chatThreadStore,
                              assistantIndex < store.messages.count else { return }
                        store.messages[assistantIndex].content += token
                    }
                }
                chatThreadStore.persistMessages()

                if isNewThread, let threadID = threadID {
                    self.generateTitle(
                        for: threadID,
                        messages: chatThreadStore.messages,
                        settingsVM: settingsVM,
                        chatThreadStore: chatThreadStore
                    )
                }
            } catch {
                self.errorMessage = error.localizedDescription
                if assistantIndex < chatThreadStore.messages.count,
                   chatThreadStore.messages[assistantIndex].content.isEmpty {
                    chatThreadStore.messages.remove(at: assistantIndex)
                    chatThreadStore.persistMessages()
                }
            }
            self.isStreaming = false
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
    }

    func newConversation(chatThreadStore: ChatThreadStore, profileID: UUID) {
        chatThreadStore.selectedThreadID = nil
        chatThreadStore.messages = []
        errorMessage = nil
    }

    // MARK: - Title Generation

    private func generateTitle(
        for threadID: UUID,
        messages: [ChatMessage],
        settingsVM: SettingsViewModel,
        chatThreadStore: ChatThreadStore
    ) {
        guard let config = settingsVM.activeProvider else { return }
        let apiKey = settingsVM.apiKey(for: config.type)
        guard !apiKey.isEmpty else { return }

        let userMsg = messages.first { $0.role == .user }?.content ?? ""
        let assistantMsg = messages.first { $0.role == .assistant }?.content ?? ""

        let titleMessages: [(role: String, content: String)] = [
            (role: "system", content: "Generate a short title (3-6 words) for this conversation. Reply with ONLY the title, no quotes."),
            (role: "user", content: userMsg),
            (role: "assistant", content: assistantMsg),
            (role: "user", content: "Generate a short title for this conversation.")
        ]

        let service = LLMService(config: config, apiKey: apiKey)

        Task {
            do {
                let title = try await service.completeChat(messages: titleMessages)
                let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    chatThreadStore.updateThreadTitle(threadID, title: trimmed)
                }
            } catch {
                // Keep default title on failure
            }
        }
    }
}
