import Foundation
import HuggingFace
import MLXLMCommon
import MLXLLM
import MLX
import Tokenizers

actor LocalLLMService {
    private var modelContainer: ModelContainer?
    private var chatSession: ChatSession?
    private var currentModelId: String?
    private var currentConversationId: UUID?

    var isReady: Bool { modelContainer != nil }

    func loadModel(id: String) async throws {
        // Set GPU cache limit for iOS memory constraints
        Memory.cacheLimit = 512 * 1024 * 1024

        let modelConfig = ModelConfiguration(id: id)
        let container = try await LLMModelFactory.shared.loadContainer(
            from: HuggingFaceHubDownloader(),
            using: TransformersTokenizerLoader(),
            configuration: modelConfig
        ) { progress in
            Task { @MainActor in
                NotificationCenter.default.post(
                    name: .localModelDownloadProgress,
                    object: progress.fractionCompleted
                )
            }
        }

        modelContainer = container
        currentModelId = id
        chatSession = nil
        currentConversationId = nil
    }

    /// Stream a response for a new user message, reusing KV cache from previous turns.
    /// On first call or when conversationId changes, creates a new ChatSession with the system prompt.
    func streamResponse(
        userMessage: String,
        systemPrompt: String,
        conversationId: UUID,
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        guard let container = modelContainer else {
            throw LLMError.noProvider
        }

        // Reset session if conversation changed
        if conversationId != currentConversationId || chatSession == nil {
            chatSession = ChatSession(
                container,
                instructions: systemPrompt,
                generateParameters: GenerateParameters(
                    maxTokens: 1024,
                    temperature: 0.3,
                    topP: 0.9
                ),
                additionalContext: [
                    "enable_thinking": false
                ]
            )
            currentConversationId = conversationId
        }

        guard let session = chatSession else {
            throw LLMError.noProvider
        }

        return try await collectResponse(from: session, to: userMessage, onToken: onToken)
    }

    /// Run a one-off prompt against the currently loaded model without mutating the shared chat session.
    func completeDetachedResponse(
        userMessage: String,
        systemPrompt: String
    ) async throws -> String {
        guard let container = modelContainer else {
            throw LLMError.noProvider
        }

        let detachedSession = ChatSession(
            container,
            instructions: systemPrompt,
            generateParameters: GenerateParameters(
                maxTokens: 512,
                temperature: 0.2,
                topP: 0.9
            ),
            additionalContext: [
                "enable_thinking": false
            ]
        )

        return try await collectResponse(from: detachedSession, to: userMessage) { _ in }
    }

    /// Reset the chat session (e.g. when starting a new conversation)
    func resetSession() {
        chatSession = nil
        currentConversationId = nil
    }

    func unload() {
        chatSession = nil
        modelContainer = nil
        currentModelId = nil
        currentConversationId = nil
        Memory.clearCache()
    }

    private func collectResponse(
        from session: ChatSession,
        to userMessage: String,
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> String {
        var accumulated = ""
        var insideThink = false

        for try await chunk in session.streamResponse(to: userMessage) {
            // Filter out any <think>...</think> content that slips through.
            var text = chunk
            if text.contains("<think>") {
                insideThink = true
                text = text.components(separatedBy: "<think>").first ?? ""
            }
            if insideThink {
                if text.contains("</think>") {
                    insideThink = false
                    text = text.components(separatedBy: "</think>").last ?? ""
                } else {
                    continue
                }
            }
            if !text.isEmpty {
                accumulated += text
                onToken(text)
            }
        }

        return accumulated
    }
}

extension Notification.Name {
    static let localModelDownloadProgress = Notification.Name("localModelDownloadProgress")
}

private struct HuggingFaceHubDownloader: MLXLMCommon.Downloader {
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        guard let repoID = HuggingFace.Repo.ID(rawValue: id) else {
            throw MLXLMHuggingFaceError.invalidRepositoryID(id)
        }

        return try await HubClient().downloadSnapshot(
            of: repoID,
            revision: revision ?? "main",
            matching: patterns,
            progressHandler: { @MainActor progress in
                progressHandler(progress)
            }
        )
    }
}

private struct TransformersTokenizerLoader: MLXLMCommon.TokenizerLoader {
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let upstream = try await AutoTokenizer.from(modelFolder: directory)
        return TokenizerBridge(upstream)
    }
}

private struct TokenizerBridge: MLXLMCommon.Tokenizer {
    private let upstream: any Tokenizers.Tokenizer

    init(_ upstream: any Tokenizers.Tokenizer) {
        self.upstream = upstream
    }

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        upstream.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        upstream.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        upstream.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        upstream.convertIdToToken(id)
    }

    var bosToken: String? { upstream.bosToken }
    var eosToken: String? { upstream.eosToken }
    var unknownToken: String? { upstream.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        do {
            return try upstream.applyChatTemplate(
                messages: messages,
                tools: tools,
                additionalContext: additionalContext
            )
        } catch Tokenizers.TokenizerError.missingChatTemplate {
            throw MLXLMCommon.TokenizerError.missingChatTemplate
        }
    }
}

private enum MLXLMHuggingFaceError: LocalizedError {
    case invalidRepositoryID(String)

    var errorDescription: String? {
        switch self {
        case .invalidRepositoryID(let id):
            return "Invalid Hugging Face repository ID: '\(id)'. Expected format 'namespace/name'."
        }
    }
}
