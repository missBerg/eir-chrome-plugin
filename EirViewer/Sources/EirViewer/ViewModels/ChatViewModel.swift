import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var inputText: String = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    private var streamingTask: Task<Void, Never>?

    func sendMessage(document: EirDocument?, settingsVM: SettingsViewModel) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)
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
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        let systemPrompt = SystemPrompt.build(from: document)
        var llmMessages: [(role: String, content: String)] = [
            (role: "system", content: systemPrompt)
        ]
        for msg in messages.dropLast() {
            switch msg.role {
            case .user: llmMessages.append((role: "user", content: msg.content))
            case .assistant: llmMessages.append((role: "assistant", content: msg.content))
            case .system: break
            }
        }

        let service = LLMService(config: config, apiKey: apiKey)
        let capturedMessages = llmMessages

        streamingTask = Task {
            do {
                try await service.streamChat(messages: capturedMessages) { [weak self] token in
                    Task { @MainActor in
                        self?.messages[assistantIndex].content += token
                    }
                }
            } catch {
                self.errorMessage = error.localizedDescription
                if self.messages[assistantIndex].content.isEmpty {
                    self.messages.remove(at: assistantIndex)
                }
            }
            self.isStreaming = false
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
    }

    func clearChat() {
        messages.removeAll()
        errorMessage = nil
    }
}
