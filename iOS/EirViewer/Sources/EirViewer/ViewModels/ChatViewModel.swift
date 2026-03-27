import SwiftUI

@MainActor
class ChatViewModel: ObservableObject {
    @Published var inputText: String = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?
    @Published var pendingCloudConsent: LLMProviderType?

    private var streamingTask: Task<Void, Never>?
    private let toolRegistry = ToolRegistry()
    private let maxToolIterations = 5

    // Pending message state for consent flow
    private var pendingSendArgs: (EirDocument?, SettingsViewModel, ChatThreadStore, UUID, AgentMemoryStore, LocalModelManager?)?
    private var pendingVoiceNoteArgs: (RecordedVoiceNoteDraft, EirDocument?, SettingsViewModel, ChatThreadStore, UUID, AgentMemoryStore, LocalModelManager?)?

    static func hasCloudConsent(for provider: LLMProviderType) -> Bool {
        UserDefaults.standard.bool(forKey: "cloudConsent_\(provider.rawValue)")
    }

    static func grantCloudConsent(for provider: LLMProviderType) {
        UserDefaults.standard.set(true, forKey: "cloudConsent_\(provider.rawValue)")
    }

    func consentGrantedAndSend() {
        guard let provider = pendingCloudConsent else { return }
        Self.grantCloudConsent(for: provider)
        pendingCloudConsent = nil
        if let args = pendingSendArgs {
            pendingSendArgs = nil
            Task {
                do {
                    if provider.usesManagedTrialAccess,
                       let config = args.1.providers.first(where: { $0.type == provider }) {
                        _ = try await args.1.provisionManagedAccess(for: config)
                    }

                    sendMessage(
                        document: args.0,
                        settingsVM: args.1,
                        chatThreadStore: args.2,
                        profileID: args.3,
                        agentMemoryStore: args.4,
                        localModelManager: args.5
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } else if let args = pendingVoiceNoteArgs {
            pendingVoiceNoteArgs = nil
            Task {
                do {
                    if provider.usesManagedTrialAccess,
                       let config = args.2.providers.first(where: { $0.type == provider }) {
                        _ = try await args.2.provisionManagedAccess(for: config)
                    }

                    await sendVoiceNote(
                        args.0,
                        document: args.1,
                        settingsVM: args.2,
                        chatThreadStore: args.3,
                        profileID: args.4,
                        agentMemoryStore: args.5,
                        localModelManager: args.6
                    )
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    func consentDenied() {
        pendingCloudConsent = nil
        pendingSendArgs = nil
        pendingVoiceNoteArgs = nil
    }

    func sendMessage(
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        chatThreadStore: ChatThreadStore,
        profileID: UUID,
        agentMemoryStore: AgentMemoryStore,
        localModelManager: LocalModelManager? = nil
    ) {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming else { return }

        guard let config = settingsVM.activeProvider else {
            errorMessage = "No LLM provider selected. Configure one in Settings."
            return
        }

        // Check cloud consent before sending data to third-party providers
        if !config.type.isLocal && !Self.hasCloudConsent(for: config.type) {
            pendingSendArgs = (document, settingsVM, chatThreadStore, profileID, agentMemoryStore, localModelManager)
            pendingCloudConsent = config.type
            return
        }

        // Auto-create thread if none selected
        if chatThreadStore.selectedThreadID == nil {
            chatThreadStore.createThread(profileID: profileID)
        }

        let userMessage = ChatMessage(role: .user, content: text)
        chatThreadStore.addMessage(userMessage)
        inputText = ""

        // Validate provider readiness
        if config.type.isLocal {
            guard let manager = localModelManager, manager.isReady else {
                errorMessage = "On-device model not loaded. Download it in Settings first."
                return
            }
        } else if config.type.requiresUserAPIKey {
            let credential = settingsVM.apiKey(for: config.type)
            guard !credential.isEmpty else {
                errorMessage = "No API key set for \(config.type.rawValue). Add one in Settings."
                return
            }
        }

        isStreaming = true
        errorMessage = nil

        let assistantMessage = ChatMessage(role: .assistant, content: "")
        chatThreadStore.addMessage(assistantMessage)
        let assistantIndex = chatThreadStore.messages.count - 1

        let systemPrompt = SystemPrompt.build(
            memory: agentMemoryStore.memory,
            document: document,
            includeToolInstructions: !config.type.isLocal
        )

        // Build LLM messages from conversation history
        var llmMessages: [LLMMessage] = [.system(systemPrompt)]
        for msg in chatThreadStore.messages.dropLast() {
            switch msg.role {
            case .user:
                llmMessages.append(.user(msg.content))
            case .assistant:
                if let toolCalls = msg.toolCalls, !toolCalls.isEmpty {
                    llmMessages.append(.assistantToolCalls(msg.content, toolCalls))
                } else {
                    llmMessages.append(.assistant(msg.content))
                }
            case .tool:
                if let toolCallId = msg.toolCallId {
                    llmMessages.append(.toolResult(ToolResult(toolCallId: toolCallId, content: msg.content)))
                }
            case .system:
                break
            }
        }

        let isNewThread = chatThreadStore.messages.count == 2
        let threadID = chatThreadStore.selectedThreadID

        if config.type.isLocal {
            // Local on-device inference — use ChatSession with KV cache for fast responses
            let localService = localModelManager!.service
            let userName = document?.metadata.patient?.name
            let activeVersion = settingsVM.activePromptVersion
            let localPrompt = SystemPrompt.buildLocal(document: document, userName: userName, promptVersion: activeVersion)
            let conversationId = chatThreadStore.selectedThreadID ?? UUID()

            streamingTask = Task {
                do {
                    _ = try await localService.streamResponse(
                        userMessage: text,
                        systemPrompt: localPrompt,
                        conversationId: conversationId
                    ) { [weak chatThreadStore] token in
                        Task { @MainActor in
                            guard let store = chatThreadStore,
                                  assistantIndex < store.messages.count else { return }
                            store.messages[assistantIndex].content += token
                        }
                    }

                    chatThreadStore.persistMessages()

                    // Generate title using local model
                    if isNewThread, let threadID = threadID {
                        self.generateLocalTitle(
                            for: threadID,
                            messages: chatThreadStore.messages,
                            localService: localService,
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
        } else {
            // Cloud provider — full agent loop with tools
            let tools = ToolRegistry.tools
            let toolContext = ToolContext(document: document, agentMemoryStore: agentMemoryStore)

            streamingTask = Task {
                do {
                    let credential = try await settingsVM.resolvedCredential(for: config)
                    let service = LLMService(config: config, apiKey: credential)

                    try await runAgentLoop(
                        service: service,
                        messages: &llmMessages,
                        tools: tools,
                        toolContext: toolContext,
                        chatThreadStore: chatThreadStore,
                        assistantIndex: assistantIndex,
                        iteration: 0
                    )

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
    }

    // MARK: - Agent Loop

    private func runAgentLoop(
        service: LLMService,
        messages: inout [LLMMessage],
        tools: [ToolDefinition],
        toolContext: ToolContext,
        chatThreadStore: ChatThreadStore,
        assistantIndex: Int,
        iteration: Int
    ) async throws {
        guard iteration < maxToolIterations else { return }

        let result = try await service.streamChatWithTools(
            messages: messages,
            tools: tools
        ) { [weak chatThreadStore] token in
            Task { @MainActor in
                guard let store = chatThreadStore,
                      assistantIndex < store.messages.count else { return }
                store.messages[assistantIndex].content += token
            }
        }

        switch result {
        case .text:
            // Final text response — done
            return

        case .toolCalls(let calls):
            // Store the tool calls on the assistant message
            chatThreadStore.messages[assistantIndex].toolCalls = calls

            // Execute each tool and collect results
            var toolResults: [ToolResult] = []
            for call in calls {
                let toolResult = await toolRegistry.execute(call: call, context: toolContext)
                toolResults.append(toolResult)

                // Add tool result as a hidden message in the thread
                let toolMsg = ChatMessage(role: .tool, content: toolResult.content, toolCallId: toolResult.toolCallId)
                chatThreadStore.addMessage(toolMsg)
            }

            // Add tool call and results to LLM message history
            let assistantContent = chatThreadStore.messages[assistantIndex].content
            messages.append(.assistantToolCalls(assistantContent, calls))
            for tr in toolResults {
                messages.append(.toolResult(tr))
            }

            // Create a new assistant message for the follow-up response
            let followUpMessage = ChatMessage(role: .assistant, content: "")
            chatThreadStore.addMessage(followUpMessage)
            let newIndex = chatThreadStore.messages.count - 1

            // Recurse
            try await runAgentLoop(
                service: service,
                messages: &messages,
                tools: tools,
                toolContext: toolContext,
                chatThreadStore: chatThreadStore,
                assistantIndex: newIndex,
                iteration: iteration + 1
            )
        }
    }

    func stopStreaming() {
        streamingTask?.cancel()
        isStreaming = false
    }

    func sendVoiceNote(
        _ draft: RecordedVoiceNoteDraft,
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        chatThreadStore: ChatThreadStore,
        profileID: UUID,
        agentMemoryStore: AgentMemoryStore,
        localModelManager: LocalModelManager? = nil
    ) async {
        guard !isStreaming else { return }
        guard let config = settingsVM.activeProvider else {
            errorMessage = "No LLM provider selected. Configure one in Settings."
            return
        }

        guard config.type.usesManagedTrialAccess else {
            errorMessage = "Voice notes are currently available with Free Trial for Eir."
            return
        }

        if !Self.hasCloudConsent(for: config.type) {
            pendingVoiceNoteArgs = (draft, document, settingsVM, chatThreadStore, profileID, agentMemoryStore, localModelManager)
            pendingCloudConsent = config.type
            return
        }

        if chatThreadStore.selectedThreadID == nil {
            chatThreadStore.createThread(profileID: profileID)
        }

        let voiceNote = VoiceNoteAttachment(
            id: UUID(),
            localFilePath: draft.fileURL.path,
            duration: draft.duration,
            waveform: draft.waveform,
            status: .transcribing,
            transcript: nil,
            errorMessage: nil,
            mimeType: draft.mimeType
        )
        let message = ChatMessage(role: .user, content: "", voiceNote: voiceNote)
        chatThreadStore.addMessage(message)

        do {
            let transcript = try await VoiceNoteTranscriptionService.transcribe(draft: draft, settingsVM: settingsVM)
            guard !transcript.isEmpty else {
                throw LLMError.requestFailed("The voice note could not be turned into text.")
            }

            chatThreadStore.updateMessage(id: message.id) { current in
                current.content = transcript
                current.voiceNote?.status = .ready
                current.voiceNote?.transcript = transcript
                current.voiceNote?.errorMessage = nil
            }

            inputText = transcript
            sendMessage(
                document: document,
                settingsVM: settingsVM,
                chatThreadStore: chatThreadStore,
                profileID: profileID,
                agentMemoryStore: agentMemoryStore,
                localModelManager: localModelManager
            )
        } catch {
            errorMessage = error.localizedDescription
            chatThreadStore.updateMessage(id: message.id) { current in
                current.voiceNote?.status = .failed
                current.voiceNote?.errorMessage = error.localizedDescription
            }
        }
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

        let userMsg = messages.first { $0.role == .user }?.content ?? ""
        let assistantMsg = messages.first { $0.role == .assistant }?.content ?? ""

        let titleMessages: [(role: String, content: String)] = [
            (role: "system", content: "Generate a short title (3-6 words) for this conversation. Reply with ONLY the title, no quotes."),
            (role: "user", content: userMsg),
            (role: "assistant", content: assistantMsg),
            (role: "user", content: "Generate a short title for this conversation.")
        ]

        Task {
            do {
                let credential = try await settingsVM.resolvedCredential(for: config)
                let service = LLMService(config: config, apiKey: credential)
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

    private func generateLocalTitle(
        for threadID: UUID,
        messages: [ChatMessage],
        localService: LocalLLMService,
        chatThreadStore: ChatThreadStore
    ) {
        // Use truncated first user message as title to avoid a slow second inference call
        let userMsg = messages.first { $0.role == .user }?.content ?? "New Chat"
        let words = userMsg.split(separator: " ").prefix(6).joined(separator: " ")
        let title = words.isEmpty ? "New Chat" : words
        chatThreadStore.updateThreadTitle(threadID, title: title)
    }

    // MARK: - Explain Entry

    func explainEntry(
        _ entry: EirEntry,
        document: EirDocument?,
        settingsVM: SettingsViewModel,
        chatThreadStore: ChatThreadStore,
        profileID: UUID,
        agentMemoryStore: AgentMemoryStore,
        localModelManager: LocalModelManager? = nil
    ) {
        // Build a prompt from the entry content
        var prompt = "Explain this medical record:\n\n"
        if let date = entry.date { prompt += "Date: \(date)\n" }
        if let category = entry.category { prompt += "Category: \(category)\n" }
        if let summary = entry.content?.summary { prompt += "Summary: \(summary)\n" }
        if let type = entry.type { prompt += "Type: \(type)\n" }
        if let provider = entry.provider?.name { prompt += "Provider: \(provider)\n" }
        if let details = entry.content?.details { prompt += "Details: \(details)\n" }
        if let notes = entry.content?.notes, !notes.isEmpty {
            prompt += "Notes: \(notes.joined(separator: "; "))\n"
        }

        // Start a new conversation and send the message
        newConversation(chatThreadStore: chatThreadStore, profileID: profileID)
        inputText = prompt

        // Switch to chat tab first, then sendMessage will handle consent if needed
        NotificationCenter.default.post(name: .navigateToChat, object: nil)

        sendMessage(
            document: document,
            settingsVM: settingsVM,
            chatThreadStore: chatThreadStore,
            profileID: profileID,
            agentMemoryStore: agentMemoryStore,
            localModelManager: localModelManager
        )
    }
}

extension Notification.Name {
    static let navigateToChat = Notification.Name("navigateToChat")
}
