import Foundation

enum LLMError: LocalizedError {
    case noProvider
    case noAPIKey
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noProvider: return "No LLM provider configured"
        case .noAPIKey: return "No API key set for this provider"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .invalidResponse: return "Invalid response from LLM"
        }
    }
}

// MARK: - LLM Message (tool-aware)

enum LLMMessage {
    case system(String)
    case user(String)
    case assistant(String)
    case assistantToolCalls(String, [ToolCall])  // content + tool calls
    case toolResult(ToolResult)
}

// MARK: - Stream Result

enum StreamResult {
    case text(String)          // Final accumulated text
    case toolCalls([ToolCall]) // LLM wants to call tools
}

struct OpenAICodexStreamAccumulator {
    let responseContentType: String

    private var bufferedEventType: String?
    private var bufferedData: [String] = []
    private var accumulatedContent = ""
    private var toolCalls: [ToolCall] = []
    private var sawCodexEvent = false
    private var rawResponseLines: [String] = []
    private var pendingFunctionCallArguments: [String: String] = [:]
    private var debugEventTrace: [String] = []

    init(responseContentType: String) {
        self.responseContentType = responseContentType
    }

    var parserEvents: [String] {
        debugEventTrace
    }

    mutating func consume(
        rawLine: String,
        onToken: (String) -> Void
    ) throws {
        let line = rawLine.trimmingCharacters(in: .newlines)
        if line.isEmpty {
            try flushEvent(onToken: onToken)
            return
        }

        if line.hasPrefix("event:") {
            bufferedEventType = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
        } else if line.hasPrefix("data:") {
            let dataLine = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            if dataLine != "[DONE]" {
                bufferedData.append(dataLine)
            }
        } else {
            rawResponseLines.append(line)
            if line.first == "{" || line.first == "[" {
                bufferedData.append(line)
            }
        }
    }

    mutating func finish(
        onToken: (String) -> Void
    ) throws -> StreamResult {
        try flushEvent(onToken: onToken)

        if !toolCalls.isEmpty {
            return .toolCalls(toolCalls)
        }

        if !sawCodexEvent {
            let preview = rawResponseLines
                .prefix(6)
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !preview.isEmpty {
                throw LLMError.requestFailed(
                    "ChatGPT account stream closed before readable Codex events arrived. Content-Type: \(responseContentType). Preview: \(preview)"
                )
            }
            throw LLMError.requestFailed(
                "ChatGPT account stream closed before readable Codex events arrived. Content-Type: \(responseContentType)."
            )
        }

        return .text(accumulatedContent)
    }

    private func extractMessageText(from item: [String: Any]) -> String {
        guard let content = item["content"] as? [[String: Any]] else { return "" }
        return content.compactMap { part -> String? in
            if let value = part["text"] as? String { return value }
            if let value = part["refusal"] as? String { return value }
            return nil
        }.joined()
    }

    private mutating func appendTextIfNeeded(
        _ text: String,
        onToken: (String) -> Void
    ) {
        guard !text.isEmpty else { return }
        if accumulatedContent.isEmpty {
            accumulatedContent = text
            onToken(text)
        }
    }

    private mutating func flushEvent(
        onToken: (String) -> Void
    ) throws {
        guard !bufferedData.isEmpty else { return }
        let payload = bufferedData.joined(separator: "\n")
        defer {
            bufferedEventType = nil
            bufferedData.removeAll(keepingCapacity: true)
        }

        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        let eventType = bufferedEventType ?? (json["type"] as? String)
        guard let eventType, !eventType.isEmpty else { return }
        sawCodexEvent = true
        if debugEventTrace.last != eventType {
            debugEventTrace.append(eventType)
            if debugEventTrace.count > 12 {
                debugEventTrace.removeFirst(debugEventTrace.count - 12)
            }
        }

        switch eventType {
        case "response.output_item.added":
            if accumulatedContent.isEmpty,
               let item = json["item"] as? [String: Any],
               (item["type"] as? String) == "message" {
                appendTextIfNeeded(extractMessageText(from: item), onToken: onToken)
            }
        case "response.output_text.delta":
            if let delta = json["delta"] as? String, !delta.isEmpty {
                accumulatedContent += delta
                onToken(delta)
            }
        case "response.function_call_arguments.delta":
            guard let delta = json["delta"] as? String, !delta.isEmpty else { return }
            let itemID = (json["item_id"] as? String)
                ?? (json["item"] as? [String: Any])?["id"] as? String
                ?? "pending"
            pendingFunctionCallArguments[itemID, default: ""] += delta
        case "response.output_item.done":
            guard let item = json["item"] as? [String: Any],
                  let itemType = item["type"] as? String else {
                return
            }

            if itemType == "message" {
                appendTextIfNeeded(extractMessageText(from: item), onToken: onToken)
            } else if itemType == "function_call" {
                let callID = item["call_id"] as? String ?? UUID().uuidString
                let itemID = item["id"] as? String ?? UUID().uuidString
                let name = item["name"] as? String ?? ""
                let arguments = pendingFunctionCallArguments.removeValue(forKey: itemID)
                    ?? item["arguments"] as? String
                    ?? "{}"
                toolCalls.append(ToolCall(id: "\(callID)|\(itemID)", name: name, arguments: arguments))
            }
        case "response.completed":
            if accumulatedContent.isEmpty,
               let response = json["response"] as? [String: Any],
               let output = response["output"] as? [[String: Any]] {
                for item in output {
                    guard (item["type"] as? String) == "message" else { continue }
                    let text = extractMessageText(from: item)
                    guard !text.isEmpty else { continue }
                    appendTextIfNeeded(text, onToken: onToken)
                    break
                }
            }
        case "response.failed":
            if let response = json["response"] as? [String: Any],
               let error = response["error"] as? [String: Any] {
                let message = (error["message"] as? String) ?? "Unknown error"
                let code = (error["code"] as? String) ?? ""
                throw LLMError.requestFailed(code.isEmpty ? message : "\(message) (\(code))")
            }
            throw LLMError.requestFailed(payload)
        case "error":
            let message = (json["message"] as? String) ?? payload
            let code = (json["code"] as? String) ?? ""
            throw LLMError.requestFailed(code.isEmpty ? message : "\(message) (\(code))")
        default:
            break
        }
    }
}

actor LLMService {
    private let config: LLMProviderConfig
    private let apiKey: String
    private let openAICodexBaseURL = "https://chatgpt.com/backend-api"
    private let openAICodexAuthClaim = "https://api.openai.com/auth"
    private let openAICodexInstallationIDKey = "eir_openai_codex_installation_id_v1"
    private let openAICodexPreviewByteLimit = 4096

    init(config: LLMProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    // MARK: - Existing methods (backward compat)

    func completeChat(
        messages: [(role: String, content: String)]
    ) async throws -> String {
        nonisolated(unsafe) var result = ""
        try await streamChat(messages: messages) { token in
            result += token
        }
        return result
    }

    func streamChat(
        messages: [(role: String, content: String)],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws {
        if usesOpenAICodexAuth {
            try await streamOpenAICodex(messages: messages, onToken: onToken)
            return
        }
        if config.type.usesOpenAICompat {
            try await streamOpenAICompat(messages: messages, onToken: onToken)
        } else {
            try await streamAnthropic(messages: messages, onToken: onToken)
        }
    }

    // MARK: - Tool-aware streaming

    func streamChatWithTools(
        messages: [LLMMessage],
        tools: [ToolDefinition],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> StreamResult {
        if usesOpenAICodexAuth {
            return try await streamOpenAICodexWithTools(messages: messages, tools: tools, onToken: onToken)
        }
        if config.type.usesOpenAICompat {
            return try await streamOpenAICompatWithTools(messages: messages, tools: tools, onToken: onToken)
        } else {
            return try await streamAnthropicWithTools(messages: messages, tools: tools, onToken: onToken)
        }
    }

    // MARK: - OpenAI Codex / ChatGPT Account

    private var usesOpenAICodexAuth: Bool {
        config.type == .openai && openAICodexAccountID(from: apiKey) != nil
    }

    private func streamOpenAICodex(
        messages: [(role: String, content: String)],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws {
        let llmMessages = messages.map { message -> LLMMessage in
            switch message.role {
            case "system":
                return .system(message.content)
            case "assistant":
                return .assistant(message.content)
            default:
                return .user(message.content)
            }
        }

        let result = try await streamOpenAICodexWithTools(messages: llmMessages, tools: [], onToken: onToken)
        if case .toolCalls = result {
            throw LLMError.requestFailed("ChatGPT account response returned tools for a plain chat request.")
        }
    }

    private func streamOpenAICodexWithTools(
        messages: [LLMMessage],
        tools: [ToolDefinition],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> StreamResult {
        guard let accountID = openAICodexAccountID(from: apiKey) else {
            throw LLMError.requestFailed("ChatGPT account token is missing an account ID.")
        }

        let url = URL(string: resolveOpenAICodexURL())!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("responses=experimental", forHTTPHeaderField: "OpenAI-Beta")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-ID")
        request.setValue("eir", forHTTPHeaderField: "originator")
        request.setValue(openAICodexClientVersion(), forHTTPHeaderField: "version")
        request.setValue(openAICodexUserAgent(), forHTTPHeaderField: "User-Agent")

        let body = buildOpenAICodexBody(messages: messages, tools: tools)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let requestMethod = request.httpMethod ?? "POST"
        let requestHeaders = sanitizedHeaders(request.allHTTPHeaderFields ?? [:])
        let requestBodySummary = openAICodexBodySummary(body)

        let diagnosticsID = await MainActor.run {
            CodexNetworkDiagnosticsStore.shared.beginRequest(
                category: "ChatGPT account",
                url: url.absoluteString,
                method: requestMethod,
                requestHeaders: requestHeaders,
                requestBodySummary: requestBodySummary
            )
        }

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            await MainActor.run {
                CodexNetworkDiagnosticsStore.shared.finish(
                    id: diagnosticsID,
                    bytesRead: 0,
                    lineCount: 0,
                    parserEvents: [],
                    rawPreview: "",
                    outcome: "Invalid response",
                    errorMessage: LLMError.invalidResponse.localizedDescription
                )
            }
            throw LLMError.invalidResponse
        }

        let responseHeaders = sanitizedHeaders(httpResponse.allHeaderFields)
        let responseContentType = httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""
        await MainActor.run {
            CodexNetworkDiagnosticsStore.shared.updateResponse(
                id: diagnosticsID,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                contentType: responseContentType
            )
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            let errorBytesRead = errorBody.utf8.count
            let errorLineCount = errorBody.isEmpty ? 0 : errorBody.split(separator: "\n").count
            let errorPreview = truncatedPreview(errorBody)
            let errorMessage = errorBody
            await MainActor.run {
                CodexNetworkDiagnosticsStore.shared.finish(
                    id: diagnosticsID,
                    bytesRead: errorBytesRead,
                    lineCount: errorLineCount,
                    parserEvents: [],
                    rawPreview: errorPreview,
                    outcome: "HTTP \(httpResponse.statusCode)",
                    errorMessage: errorMessage
                )
            }
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        var accumulator = OpenAICodexStreamAccumulator(responseContentType: responseContentType)
        var rawPreview = Data()
        var lineBuffer = Data()
        var bytesRead = 0
        var lineCount = 0

        do {
            for try await byte in bytes {
                bytesRead += 1
                if rawPreview.count < openAICodexPreviewByteLimit {
                    rawPreview.append(byte)
                }

                if byte == 0x0A {
                    let rawLine = String(decoding: lineBuffer, as: UTF8.self)
                    lineCount += 1
                    try accumulator.consume(rawLine: rawLine, onToken: onToken)
                    lineBuffer.removeAll(keepingCapacity: true)
                } else if byte != 0x0D {
                    lineBuffer.append(byte)
                }
            }

            if !lineBuffer.isEmpty {
                lineCount += 1
                let rawLine = String(decoding: lineBuffer, as: UTF8.self)
                try accumulator.consume(rawLine: rawLine, onToken: onToken)
            }

            let result = try accumulator.finish(onToken: onToken)
            let parserEvents = accumulator.parserEvents
            let preview = previewString(from: rawPreview)
            let outcome: String
            switch result {
            case .text(let text):
                outcome = text.isEmpty ? "Completed with empty text" : "Completed with text"
            case .toolCalls(let toolCalls):
                outcome = "Completed with \(toolCalls.count) tool call(s)"
            }
            let finalBytesRead = bytesRead
            let finalLineCount = lineCount
            await MainActor.run {
                CodexNetworkDiagnosticsStore.shared.finish(
                    id: diagnosticsID,
                    bytesRead: finalBytesRead,
                    lineCount: finalLineCount,
                    parserEvents: parserEvents,
                    rawPreview: preview,
                    outcome: outcome,
                    errorMessage: nil
                )
            }
            return result
        } catch {
            let parserEvents = accumulator.parserEvents
            let preview = previewString(from: rawPreview)
            let finalBytesRead = bytesRead
            let finalLineCount = lineCount
            let errorMessage = error.localizedDescription
            await MainActor.run {
                CodexNetworkDiagnosticsStore.shared.finish(
                    id: diagnosticsID,
                    bytesRead: finalBytesRead,
                    lineCount: finalLineCount,
                    parserEvents: parserEvents,
                    rawPreview: preview,
                    outcome: "Stream failed",
                    errorMessage: errorMessage
                )
            }
            throw error
        }
    }

    // MARK: - OpenAI Compatible (plain)

    private func streamOpenAICompat(
        messages: [(role: String, content: String)],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let body: [String: Any] = [
            "model": config.model,
            "messages": messages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        nonisolated(unsafe) var unexpectedLines: [String] = []
        nonisolated(unsafe) var emittedAnyContent = false

        for try await line in bytes.lines {
            if !line.hasPrefix("data: ") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    unexpectedLines.append(trimmed)
                }
                continue
            }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            emittedAnyContent = true
            onToken(content)
        }

        try throwIfUnexpectedOpenAICompatPayload(unexpectedLines, emittedAnyContent: emittedAnyContent)
    }

    // MARK: - OpenAI Compatible (with tools)

    private func streamOpenAICompatWithTools(
        messages: [LLMMessage],
        tools: [ToolDefinition],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> StreamResult {
        let url = URL(string: "\(config.baseURL)/chat/completions")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let formattedMessages = formatOpenAIMessages(messages)
        let formattedTools = formatOpenAITools(tools)

        var body: [String: Any] = [
            "model": config.model,
            "messages": formattedMessages,
            "stream": true,
        ]
        if !formattedTools.isEmpty {
            body["tools"] = formattedTools
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        nonisolated(unsafe) var accumulatedContent = ""
        nonisolated(unsafe) var toolCallsMap: [Int: (id: String, name: String, arguments: String)] = [:]
        nonisolated(unsafe) var unexpectedLines: [String] = []

        for try await line in bytes.lines {
            if !line.hasPrefix("data: ") {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    unexpectedLines.append(trimmed)
                }
                continue
            }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any] else {
                continue
            }

            // Text content
            if let content = delta["content"] as? String {
                accumulatedContent += content
                onToken(content)
            }

            // Tool calls (streamed incrementally)
            if let toolCalls = delta["tool_calls"] as? [[String: Any]] {
                for tc in toolCalls {
                    guard let index = tc["index"] as? Int else { continue }
                    if let id = tc["id"] as? String {
                        toolCallsMap[index] = (id: id, name: "", arguments: "")
                    }
                    if let function = tc["function"] as? [String: Any] {
                        if let name = function["name"] as? String {
                            toolCallsMap[index]?.name = name
                        }
                        if let args = function["arguments"] as? String {
                            toolCallsMap[index]?.arguments += args
                        }
                    }
                }
            }
        }

        if !toolCallsMap.isEmpty {
            let calls = toolCallsMap.sorted { $0.key < $1.key }.map { (_, v) in
                ToolCall(id: v.id, name: v.name, arguments: v.arguments)
            }
            return .toolCalls(calls)
        }

        try throwIfUnexpectedOpenAICompatPayload(unexpectedLines, emittedAnyContent: !accumulatedContent.isEmpty)
        return .text(accumulatedContent)
    }

    // MARK: - Anthropic (plain)

    private func streamAnthropic(
        messages: [(role: String, content: String)],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws {
        let url = URL(string: "\(config.baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let systemMessage = messages.first(where: { $0.role == "system" })?.content ?? ""
        let chatMessages = messages.filter { $0.role != "system" }

        let body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "system": systemMessage,
            "messages": chatMessages.map { ["role": $0.role, "content": $0.content] },
            "stream": true,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String
            if eventType == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                onToken(text)
            } else if eventType == "message_stop" {
                break
            }
        }
    }

    // MARK: - Anthropic (with tools)

    private func streamAnthropicWithTools(
        messages: [LLMMessage],
        tools: [ToolDefinition],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws -> StreamResult {
        let url = URL(string: "\(config.baseURL)/messages")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let (systemPrompt, formattedMessages) = formatAnthropicMessages(messages)
        let formattedTools = formatAnthropicTools(tools)

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": 4096,
            "system": systemPrompt,
            "messages": formattedMessages,
            "stream": true,
        ]
        if !formattedTools.isEmpty {
            body["tools"] = formattedTools
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            var errorBody = ""
            for try await line in bytes.lines {
                errorBody += line
            }
            throw LLMError.requestFailed("HTTP \(httpResponse.statusCode): \(errorBody)")
        }

        nonisolated(unsafe) var accumulatedContent = ""
        nonisolated(unsafe) var currentToolUse: (id: String, name: String, inputJson: String)?
        nonisolated(unsafe) var toolCalls: [ToolCall] = []

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let eventType = json["type"] as? String

            switch eventType {
            case "content_block_start":
                if let contentBlock = json["content_block"] as? [String: Any],
                   let blockType = contentBlock["type"] as? String,
                   blockType == "tool_use" {
                    let id = contentBlock["id"] as? String ?? UUID().uuidString
                    let name = contentBlock["name"] as? String ?? ""
                    currentToolUse = (id: id, name: name, inputJson: "")
                }

            case "content_block_delta":
                if let delta = json["delta"] as? [String: Any] {
                    let deltaType = delta["type"] as? String
                    if deltaType == "text_delta", let text = delta["text"] as? String {
                        accumulatedContent += text
                        onToken(text)
                    } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                        currentToolUse?.inputJson += partial
                    }
                }

            case "content_block_stop":
                if let tu = currentToolUse {
                    toolCalls.append(ToolCall(id: tu.id, name: tu.name, arguments: tu.inputJson))
                    currentToolUse = nil
                }

            case "message_stop":
                break

            default:
                break
            }
        }

        if !toolCalls.isEmpty {
            return .toolCalls(toolCalls)
        }

        return .text(accumulatedContent)
    }

    // MARK: - Message Formatting (OpenAI)

    private func formatOpenAIMessages(_ messages: [LLMMessage]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for msg in messages {
            switch msg {
            case .system(let content):
                result.append(["role": "system", "content": content])
            case .user(let content):
                result.append(["role": "user", "content": content])
            case .assistant(let content):
                result.append(["role": "assistant", "content": content])
            case .assistantToolCalls(let content, let calls):
                var m: [String: Any] = ["role": "assistant"]
                if !content.isEmpty { m["content"] = content }
                m["tool_calls"] = calls.map { call -> [String: Any] in
                    [
                        "id": call.id,
                        "type": "function",
                        "function": [
                            "name": call.name,
                            "arguments": call.arguments,
                        ] as [String: Any],
                    ]
                }
                result.append(m)
            case .toolResult(let tr):
                result.append([
                    "role": "tool",
                    "tool_call_id": tr.toolCallId,
                    "content": tr.content,
                ])
            }
        }
        return result
    }

    private func formatOpenAITools(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map { tool -> [String: Any] in
            [
                "type": "function",
                "function": [
                    "name": tool.name,
                    "description": tool.description,
                    "parameters": encodeToolParameters(tool.parameters),
                ] as [String: Any],
            ]
        }
    }

    private func buildOpenAICodexBody(
        messages: [LLMMessage],
        tools: [ToolDefinition]
    ) -> [String: Any] {
        let (systemPrompt, input) = formatOpenAICodexMessages(messages)

        var body: [String: Any] = [
            "model": config.model,
            "store": false,
            "stream": true,
            "instructions": systemPrompt,
            "input": input,
            "tools": formatOpenAICodexTools(tools),
            "tool_choice": "auto",
            "parallel_tool_calls": true,
            "include": [],
            "client_metadata": [
                "x-codex-installation-id": openAICodexInstallationID(),
            ],
        ]

        if !config.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["text"] = ["verbosity": "medium"]
        }

        return body
    }

    private func formatOpenAICodexMessages(_ messages: [LLMMessage]) -> (String, [[String: Any]]) {
        var systemPrompt = ""
        var input: [[String: Any]] = []
        var assistantIndex = 0

        for message in messages {
            switch message {
            case .system(let content):
                if systemPrompt.isEmpty {
                    systemPrompt = content
                } else {
                    systemPrompt += "\n\n" + content
                }
            case .user(let content):
                input.append([
                    "type": "message",
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": content,
                        ]
                    ],
                ])
            case .assistant(let content):
                input.append([
                    "type": "message",
                    "role": "assistant",
                    "content": [
                        [
                            "type": "output_text",
                            "text": content,
                        ]
                    ],
                ])
                assistantIndex += 1
            case .assistantToolCalls(let content, let calls):
                if !content.isEmpty {
                    input.append([
                        "type": "message",
                        "role": "assistant",
                        "content": [
                            [
                                "type": "output_text",
                                "text": content,
                            ]
                        ],
                    ])
                    assistantIndex += 1
                }

                for (index, call) in calls.enumerated() {
                    let parts = call.id.split(separator: "|", maxSplits: 1).map(String.init)
                    let callID = parts.first ?? call.id
                    let itemID = parts.count > 1 ? parts[1] : "fc_\(assistantIndex)_\(index)"
                    input.append([
                        "type": "function_call",
                        "id": itemID,
                        "call_id": callID,
                        "name": call.name,
                        "arguments": call.arguments,
                    ])
                }
            case .toolResult(let result):
                let callID = result.toolCallId.split(separator: "|", maxSplits: 1).map(String.init).first ?? result.toolCallId
                input.append([
                    "type": "function_call_output",
                    "call_id": callID,
                    "output": result.content,
                ])
            }
        }

        return (systemPrompt, input)
    }

    private func formatOpenAICodexTools(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map { tool in
            [
                "type": "function",
                "name": tool.name,
                "description": tool.description,
                "parameters": encodeToolParameters(tool.parameters),
                "strict": false,
            ]
        }
    }

    // MARK: - Message Formatting (Anthropic)

    private func formatAnthropicMessages(_ messages: [LLMMessage]) -> (String, [[String: Any]]) {
        var systemPrompt = ""
        var result: [[String: Any]] = []

        for msg in messages {
            switch msg {
            case .system(let content):
                systemPrompt = content
            case .user(let content):
                result.append(["role": "user", "content": content])
            case .assistant(let content):
                result.append(["role": "assistant", "content": content])
            case .assistantToolCalls(let content, let calls):
                var contentBlocks: [[String: Any]] = []
                if !content.isEmpty {
                    contentBlocks.append(["type": "text", "text": content])
                }
                for call in calls {
                    var inputObj: Any = [String: Any]()
                    if let data = call.arguments.data(using: .utf8),
                       let parsed = try? JSONSerialization.jsonObject(with: data) {
                        inputObj = parsed
                    }
                    contentBlocks.append([
                        "type": "tool_use",
                        "id": call.id,
                        "name": call.name,
                        "input": inputObj,
                    ])
                }
                result.append(["role": "assistant", "content": contentBlocks])
            case .toolResult(let tr):
                result.append([
                    "role": "user",
                    "content": [
                        [
                            "type": "tool_result",
                            "tool_use_id": tr.toolCallId,
                            "content": tr.content,
                        ] as [String: Any]
                    ],
                ])
            }
        }

        return (systemPrompt, result)
    }

    private func formatAnthropicTools(_ tools: [ToolDefinition]) -> [[String: Any]] {
        tools.map { tool -> [String: Any] in
            [
                "name": tool.name,
                "description": tool.description,
                "input_schema": encodeToolParameters(tool.parameters),
            ]
        }
    }

    // MARK: - Helpers

    private func encodeToolParameters(_ params: ToolParameters) -> [String: Any] {
        var props: [String: Any] = [:]
        for (key, prop) in params.properties {
            var p: [String: Any] = [
                "type": prop.type,
                "description": prop.description,
            ]
            if let enumVals = prop.enum {
                p["enum"] = enumVals
            }
            props[key] = p
        }
        var result: [String: Any] = [
            "type": params.type,
            "properties": props,
        ]
        if let required = params.required, !required.isEmpty {
            result["required"] = required
        }
        return result
    }

    private func throwIfUnexpectedOpenAICompatPayload(
        _ lines: [String],
        emittedAnyContent: Bool
    ) throws {
        guard !emittedAnyContent, !lines.isEmpty else { return }

        let rawPayload = lines.joined(separator: "\n")
        if let data = rawPayload.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any] {
            let message = (error["message"] as? String) ?? rawPayload
            let code = (error["code"] as? String) ?? ""
            throw LLMError.requestFailed(code.isEmpty ? message : "\(message) (\(code))")
        }

        throw LLMError.requestFailed(rawPayload)
    }

    private func resolveOpenAICodexURL() -> String {
        let rawBaseURL = config.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseURL = rawBaseURL.isEmpty || rawBaseURL.contains("api.openai.com")
            ? openAICodexBaseURL
            : rawBaseURL
        let normalized = baseURL.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if normalized.hasSuffix("/codex/responses") { return normalized }
        if normalized.hasSuffix("/codex") { return normalized + "/responses" }
        return normalized + "/codex/responses"
    }

    private func openAICodexAccountID(from token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return nil }
        let payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let padding = String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload + padding),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let authClaims = json[openAICodexAuthClaim] as? [String: Any] else {
            return nil
        }

        return (authClaims["chatgpt_account_id"] as? String) ?? (authClaims["account_id"] as? String)
    }

    private func openAICodexInstallationID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: openAICodexInstallationIDKey),
           !existing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return existing
        }

        let generated = UUID().uuidString.lowercased()
        defaults.set(generated, forKey: openAICodexInstallationIDKey)
        return generated
    }

    private func openAICodexClientVersion() -> String {
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return version
        }
        if let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
           !build.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return build
        }
        return "dev"
    }

    private func openAICodexUserAgent() -> String {
        let version = openAICodexClientVersion()
        return "eir/\(version)"
    }

    private func sanitizedHeaders(_ headers: [AnyHashable: Any]) -> [String: String] {
        var result: [String: String] = [:]
        for (key, value) in headers {
            let name = String(describing: key)
            let rawValue = String(describing: value)
            switch name.lowercased() {
            case "authorization":
                result[name] = rawValue.hasPrefix("Bearer ") ? "Bearer [redacted]" : "[redacted]"
            case "chatgpt-account-id":
                result[name] = rawValue.isEmpty ? "" : "\(rawValue.prefix(6))..."
            default:
                result[name] = rawValue
            }
        }
        return result
    }

    private func openAICodexBodySummary(_ body: [String: Any]) -> String {
        let model = body["model"] as? String ?? config.model
        let stream = (body["stream"] as? Bool) == true ? "true" : "false"
        let inputCount = (body["input"] as? [[String: Any]])?.count ?? 0
        let toolCount = (body["tools"] as? [[String: Any]])?.count ?? 0
        let includeCount = (body["include"] as? [Any])?.count ?? 0
        return "model=\(model), stream=\(stream), inputItems=\(inputCount), tools=\(toolCount), include=\(includeCount)"
    }

    private func previewString(from data: Data) -> String {
        truncatedPreview(String(decoding: data, as: UTF8.self))
    }

    private func truncatedPreview(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return String(trimmed.prefix(2000))
    }
}
