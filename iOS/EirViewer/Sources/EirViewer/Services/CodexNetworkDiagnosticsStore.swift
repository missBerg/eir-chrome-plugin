import Foundation
import SwiftUI

struct CodexNetworkDiagnostic: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    var updatedAt: Date
    let category: String
    let url: String
    let method: String
    let requestHeaders: [String: String]
    let requestBodySummary: String
    var statusCode: Int?
    var responseHeaders: [String: String]
    var contentType: String
    var bytesRead: Int
    var lineCount: Int
    var parserEvents: [String]
    var rawPreview: String
    var outcome: String
    var errorMessage: String?

    var shareText: String {
        let requestHeaderLines = requestHeaders
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        let responseHeaderLines = responseHeaders
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")

        return [
            "Category: \(category)",
            "Started: \(createdAt.formatted(date: .abbreviated, time: .standard))",
            "Updated: \(updatedAt.formatted(date: .abbreviated, time: .standard))",
            "Request: \(method) \(url)",
            "Request summary: \(requestBodySummary)",
            "Request headers:\n\(requestHeaderLines.isEmpty ? "None" : requestHeaderLines)",
            "Status: \(statusCode.map(String.init) ?? "No HTTP response")",
            "Content-Type: \(contentType.isEmpty ? "None" : contentType)",
            "Bytes read: \(bytesRead)",
            "Lines read: \(lineCount)",
            "Parser events: \(parserEvents.isEmpty ? "None" : parserEvents.joined(separator: ", "))",
            "Outcome: \(outcome)",
            "Error: \(errorMessage ?? "None")",
            "Response headers:\n\(responseHeaderLines.isEmpty ? "None" : responseHeaderLines)",
            "Raw preview:\n\(rawPreview.isEmpty ? "None" : rawPreview)",
        ].joined(separator: "\n\n")
    }
}

@MainActor
final class CodexNetworkDiagnosticsStore: ObservableObject {
    static let shared = CodexNetworkDiagnosticsStore()

    @Published private(set) var entries: [CodexNetworkDiagnostic]

    private let storageKey = "eir_codex_network_diagnostics_v1"
    private let maxEntries = 12

    private init() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([CodexNetworkDiagnostic].self, from: data) else {
            self.entries = []
            return
        }
        self.entries = decoded.sorted { $0.updatedAt > $1.updatedAt }
    }

    func beginRequest(
        category: String,
        url: String,
        method: String,
        requestHeaders: [String: String],
        requestBodySummary: String
    ) -> UUID {
        let entry = CodexNetworkDiagnostic(
            id: UUID(),
            createdAt: Date(),
            updatedAt: Date(),
            category: category,
            url: url,
            method: method,
            requestHeaders: requestHeaders,
            requestBodySummary: requestBodySummary,
            statusCode: nil,
            responseHeaders: [:],
            contentType: "",
            bytesRead: 0,
            lineCount: 0,
            parserEvents: [],
            rawPreview: "",
            outcome: "Request started",
            errorMessage: nil
        )
        entries.insert(entry, at: 0)
        trimAndPersist()
        return entry.id
    }

    func updateResponse(
        id: UUID,
        statusCode: Int,
        responseHeaders: [String: String],
        contentType: String
    ) {
        mutate(id: id) { entry in
            entry.statusCode = statusCode
            entry.responseHeaders = responseHeaders
            entry.contentType = contentType
            entry.outcome = "Received HTTP response"
        }
    }

    func finish(
        id: UUID,
        bytesRead: Int,
        lineCount: Int,
        parserEvents: [String],
        rawPreview: String,
        outcome: String,
        errorMessage: String? = nil
    ) {
        mutate(id: id) { entry in
            entry.bytesRead = bytesRead
            entry.lineCount = lineCount
            entry.parserEvents = parserEvents
            entry.rawPreview = rawPreview
            entry.outcome = outcome
            entry.errorMessage = errorMessage
        }
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func mutate(id: UUID, update: (inout CodexNetworkDiagnostic) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        var entry = entries[index]
        update(&entry)
        entry.updatedAt = Date()
        entries[index] = entry
        entries.sort { $0.updatedAt > $1.updatedAt }
        trimAndPersist()
    }

    private func trimAndPersist() {
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
