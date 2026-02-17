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

actor LLMService {
    private let config: LLMProviderConfig
    private let apiKey: String

    init(config: LLMProviderConfig, apiKey: String) {
        self.config = config
        self.apiKey = apiKey
    }

    func streamChat(
        messages: [(role: String, content: String)],
        onToken: @Sendable @escaping (String) -> Void
    ) async throws {
        if config.type.usesOpenAICompat {
            try await streamOpenAICompat(messages: messages, onToken: onToken)
        } else {
            try await streamAnthropic(messages: messages, onToken: onToken)
        }
    }

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

        for try await line in bytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let payload = String(line.dropFirst(6))
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let delta = choices.first?["delta"] as? [String: Any],
                  let content = delta["content"] as? String else {
                continue
            }

            onToken(content)
        }
    }

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
}
