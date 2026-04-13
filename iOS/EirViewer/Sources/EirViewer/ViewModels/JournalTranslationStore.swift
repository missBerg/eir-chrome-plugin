import CryptoKit
import Foundation
import SwiftUI

struct JournalEntryTranslation: Codable {
    let targetLanguage: SupportedChatLanguage
    let summary: String?
    let details: String?
    let notes: [String]?
    let sourceEntryID: String?
    let sourceFingerprint: String?
    let sourceSummary: String?
    let sourceDetails: String?
    let sourceNotes: [String]?
    let translatedAt: Date
}

private struct JournalTranslationPayload: Codable {
    var translations: [String: [String: JournalEntryTranslation]]
    var selectedLanguageRawValue: String?
}

private struct JournalTranslationRequest: Encodable {
    let summary: String?
    let details: String?
    let notes: [String]?
}

private struct JournalTranslationResponse {
    let summary: String?
    let details: String?
    let notes: [String]?
}

@MainActor
final class JournalTranslationStore: ObservableObject {
    @Published private(set) var translationsByEntry: [String: [SupportedChatLanguage: JournalEntryTranslation]] = [:]
    @Published private(set) var selectedLanguage: SupportedChatLanguage?
    @Published var isTranslating = false
    @Published var progress: Double = 0
    @Published var currentEntryLabel: String?
    @Published var currentEntryIndex: Int = 0
    @Published var totalEntries: Int = 0
    @Published var errorMessage: String?

    private var currentProfileID: UUID?

    func load(for profileID: UUID?) {
        currentProfileID = profileID
        guard let profileID else {
            translationsByEntry = [:]
            selectedLanguage = nil
            return
        }

        let payload = EncryptedStore.load(JournalTranslationPayload.self, forKey: storageKey(for: profileID))
            ?? JournalTranslationPayload(translations: [:], selectedLanguageRawValue: nil)
        translationsByEntry = payload.translations.reduce(into: [:]) { partial, item in
            let mapped = item.value.reduce(into: [SupportedChatLanguage: JournalEntryTranslation]()) { inner, languageItem in
                guard let language = SupportedChatLanguage(rawValue: languageItem.key) else { return }
                inner[language] = languageItem.value
            }
            partial[item.key] = mapped
        }
        selectedLanguage = payload.selectedLanguageRawValue.flatMap(SupportedChatLanguage.init(rawValue:))
    }

    func setSelectedLanguage(_ language: SupportedChatLanguage?) {
        selectedLanguage = language
        save()
    }

    func availableLanguages(for entry: EirEntry) -> [SupportedChatLanguage] {
        SupportedChatLanguage.swedenPriorityLanguages.filter { translation(for: entry, language: $0) != nil }
    }

    func availableLanguages(for entries: [EirEntry]) -> [SupportedChatLanguage] {
        SupportedChatLanguage.swedenPriorityLanguages.filter { language in
            entries.contains { translation(for: $0, language: language) != nil }
        }
    }

    func translatedCount(for entries: [EirEntry], language: SupportedChatLanguage) -> Int {
        entries
            .filter(Self.isTranslatable)
            .reduce(into: 0) { count, entry in
                if translation(for: entry, language: language) != nil {
                    count += 1
                }
            }
    }

    func translatableCount(for entries: [EirEntry]) -> Int {
        entries.filter(Self.isTranslatable).count
    }

    func summary(for entry: EirEntry) -> String? {
        displayedTranslation(for: entry)?.summary ?? entry.content?.summary
    }

    func details(for entry: EirEntry) -> String? {
        displayedTranslation(for: entry)?.details ?? entry.content?.details
    }

    func notes(for entry: EirEntry) -> [String]? {
        if let translation = displayedTranslation(for: entry) {
            return orderedNotes(for: translation, sourceEntry: entry)
        }
        return entry.content?.notes
    }

    func hasTranslation(for entry: EirEntry, language: SupportedChatLanguage) -> Bool {
        translation(for: entry, language: language) != nil
    }

    func translateEntry(
        _ entry: EirEntry,
        to targetLanguage: SupportedChatLanguage,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async {
        await translate(entries: [entry], to: targetLanguage, settingsVM: settingsVM, localModelManager: localModelManager)
    }

    func translate(
        entries: [EirEntry],
        to targetLanguage: SupportedChatLanguage,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async {
        let translatableEntries = entries.filter(Self.isTranslatable)
        guard !translatableEntries.isEmpty else { return }

        let pendingEntries = translatableEntries.filter { translation(for: $0, language: targetLanguage) == nil }
        if pendingEntries.isEmpty {
            selectedLanguage = targetLanguage
            save()
            return
        }

        isTranslating = true
        progress = 0
        currentEntryLabel = nil
        currentEntryIndex = 0
        totalEntries = pendingEntries.count
        errorMessage = nil

        defer {
            isTranslating = false
            currentEntryLabel = nil
            currentEntryIndex = 0
            totalEntries = 0
        }

        var failedEntries: [String] = []

        for (index, entry) in pendingEntries.enumerated() {
            do {
                currentEntryIndex = index + 1
                currentEntryLabel = entry.content?.summary ?? entry.type ?? entry.id
                progress = Double(index) / Double(pendingEntries.count)
                let translation = try await requestTranslation(
                    for: entry,
                    to: targetLanguage,
                    settingsVM: settingsVM,
                    localModelManager: localModelManager
                )
                store(translation, for: entry, language: targetLanguage)
                progress = Double(index + 1) / Double(pendingEntries.count)
                save()
            } catch {
                failedEntries.append(entry.content?.summary ?? entry.type ?? entry.id)
            }
        }

        selectedLanguage = targetLanguage
        save()

        if !failedEntries.isEmpty {
            let succeeded = pendingEntries.count - failedEntries.count
            if succeeded > 0 {
                errorMessage = "Translated \(succeeded) notes. \(failedEntries.count) could not be translated this time. You can continue with the remaining notes."
            } else {
                errorMessage = "No new notes were translated. Try again or switch to a different model."
            }
        } else {
            selectedLanguage = targetLanguage
            save()
        }
    }

    private func displayedTranslation(for entry: EirEntry) -> JournalEntryTranslation? {
        guard let selectedLanguage else { return nil }
        return translation(for: entry, language: selectedLanguage)
    }

    private func translation(for entry: EirEntry, language: SupportedChatLanguage) -> JournalEntryTranslation? {
        let keys = translationKeys(for: entry)

        for key in keys {
            if let translation = translationsByEntry[key]?[language] {
                aliasIfNeeded(translation, for: entry, language: language, existingKeys: keys)
                return translation
            }
        }

        if let matched = lookupByStoredSource(entry: entry, language: language) {
            aliasIfNeeded(matched, for: entry, language: language, existingKeys: keys)
            return matched
        }

        return nil
    }

    private func store(_ translation: JournalEntryTranslation, for entry: EirEntry, language: SupportedChatLanguage) {
        for key in translationKeys(for: entry) {
            var existing = translationsByEntry[key] ?? [:]
            existing[language] = translation
            translationsByEntry[key] = existing
        }
    }

    private func translationKeys(for entry: EirEntry) -> [String] {
        let signature = stableEntrySignature(for: entry)
        if entry.id == signature {
            return [entry.id]
        }
        return [entry.id, signature]
    }

    private func stableEntrySignature(for entry: EirEntry) -> String {
        var parts: [String] = []
        parts.append(entry.date ?? "")
        parts.append(entry.time ?? "")
        parts.append(entry.category ?? "")
        parts.append(entry.type ?? "")
        parts.append(entry.provider?.name ?? "")
        parts.append(entry.provider?.region ?? "")
        parts.append(entry.provider?.location ?? "")
        parts.append(entry.status ?? "")
        parts.append(entry.responsiblePerson?.name ?? "")
        parts.append(entry.responsiblePerson?.role ?? "")
        parts.append(entry.content?.summary ?? "")
        parts.append(entry.content?.details ?? "")
        parts.append(entry.content?.notes?.joined(separator: "\n") ?? "")
        parts.append(entry.tags?.joined(separator: "|") ?? "")

        let components = parts
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\u{1F}")

        let digest = SHA256.hash(data: Data(components.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "entrysig_\(hex)"
    }

    private func lookupByStoredSource(entry: EirEntry, language: SupportedChatLanguage) -> JournalEntryTranslation? {
        let fingerprint = stableEntrySignature(for: entry)
        let summary = normalized(entry.content?.summary)
        let details = normalized(entry.content?.details)
        let notes = normalizedNotes(entry.content?.notes)

        for languageMap in translationsByEntry.values {
            guard let translation = languageMap[language] else { continue }

            if translation.sourceFingerprint == fingerprint {
                return translation
            }

            if let sourceSummary = normalized(translation.sourceSummary),
               sourceSummary == summary,
               normalized(translation.sourceDetails) == details,
               normalizedNotes(translation.sourceNotes) == notes {
                return translation
            }
        }

        return nil
    }

    private func aliasIfNeeded(
        _ translation: JournalEntryTranslation,
        for entry: EirEntry,
        language: SupportedChatLanguage,
        existingKeys: [String]
    ) {
        let missingKeys = existingKeys.filter { translationsByEntry[$0]?[language] == nil }
        guard !missingKeys.isEmpty else { return }

        for key in missingKeys {
            var languageMap = translationsByEntry[key] ?? [:]
            languageMap[language] = translation
            translationsByEntry[key] = languageMap
        }

        save()
    }

    private func normalized(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func normalizedNotes(_ notes: [String]?) -> [String]? {
        let cleaned = notes?
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard let cleaned, !cleaned.isEmpty else { return nil }
        return cleaned
    }

    private func orderedNotes(for translation: JournalEntryTranslation, sourceEntry: EirEntry) -> [String]? {
        guard let translatedNotes = normalizedNotes(translation.notes) else {
            return sourceEntry.content?.notes
        }

        if translation.targetLanguage == .swedish {
            return translatedNotes
        }

        let sourceNotes = Set(normalizedNotes(translation.sourceNotes) ?? normalizedNotes(sourceEntry.content?.notes) ?? [])
        guard !sourceNotes.isEmpty else {
            return translatedNotes
        }

        let cleanedNotes = translatedNotes.compactMap { removeEmbeddedSourceText(from: $0, sourceNotes: sourceNotes) }
        guard !cleanedNotes.isEmpty else {
            return translatedNotes
        }

        let reordered = cleanedNotes.sorted { lhs, rhs in
            let lhsMatchesSource = sourceNotes.contains(lhs)
            let rhsMatchesSource = sourceNotes.contains(rhs)
            if lhsMatchesSource == rhsMatchesSource {
                return false
            }
            return !lhsMatchesSource && rhsMatchesSource
        }

        return reordered
    }

    private func removeEmbeddedSourceText(from note: String, sourceNotes: Set<String>) -> String? {
        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedNote.isEmpty else { return nil }

        if sourceNotes.contains(trimmedNote) {
            return nil
        }

        let sourceParagraphs = Set(sourceNotes.flatMap(paragraphBlocks(from:)))
        let noteParagraphs = paragraphBlocks(from: trimmedNote)
        let filteredParagraphs = noteParagraphs.filter { !sourceParagraphs.contains($0) }

        if !filteredParagraphs.isEmpty, filteredParagraphs.count != noteParagraphs.count {
            let recombined = filteredParagraphs.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !recombined.isEmpty {
                return recombined
            }
        }

        for source in sourceNotes {
            guard !source.isEmpty else { continue }

            if trimmedNote.hasPrefix(source) {
                let remainderStart = trimmedNote.index(trimmedNote.startIndex, offsetBy: source.count)
                let remainder = trimmedNote[remainderStart...].trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    return remainder
                }
            }

            if trimmedNote.hasSuffix(source) {
                let remainderEnd = trimmedNote.index(trimmedNote.endIndex, offsetBy: -source.count)
                let remainder = trimmedNote[..<remainderEnd].trimmingCharacters(in: .whitespacesAndNewlines)
                if !remainder.isEmpty {
                    return remainder
                }
            }
        }

        return trimmedNote
    }

    private func paragraphBlocks(from text: String) -> [String] {
        text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func requestTranslation(
        for entry: EirEntry,
        to targetLanguage: SupportedChatLanguage,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async throws -> JournalEntryTranslation {
        let systemPrompt = """
        You are a precise medical translator.
        Translate the provided structured clinical note into \(targetLanguage.promptName).
        Preserve all medical meaning, dates, units, medication names, abbreviations, and line breaks.
        Do not summarize.
        Do not add warnings, commentary, or explanations.
        Return JSON only. No markdown fences. No prose before or after.
        Use exactly these keys:
        {
          "summary": string or null,
          "details": string or null,
          "notes": [string] or null
        }
        If a field is missing in the source, return null for that field.
        """

        let payload = JournalTranslationRequest(
            summary: entry.content?.summary,
            details: entry.content?.details,
            notes: entry.content?.notes
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let payloadData = try encoder.encode(payload)
        let payloadString = String(decoding: payloadData, as: UTF8.self)

        let userPrompt = """
        Translate this journal entry content to \(targetLanguage.promptName):

        \(payloadString)
        """

        let rawResponse = try await complete(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            settingsVM: settingsVM,
            localModelManager: localModelManager
        )
        let decoded = try decodeTranslation(from: rawResponse)
        return JournalEntryTranslation(
            targetLanguage: targetLanguage,
            summary: decoded.summary,
            details: decoded.details,
            notes: decoded.notes,
            sourceEntryID: entry.id,
            sourceFingerprint: stableEntrySignature(for: entry),
            sourceSummary: entry.content?.summary,
            sourceDetails: entry.content?.details,
            sourceNotes: entry.content?.notes,
            translatedAt: Date()
        )
    }

    private func complete(
        systemPrompt: String,
        userPrompt: String,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager
    ) async throws -> String {
        guard let config = settingsVM.activeProvider else {
            throw LLMError.noProvider
        }

        if config.type.isLocal {
            try await localModelManager.ensurePreferredModelLoaded()
            return try await localModelManager.service.completeDetachedResponse(
                userMessage: userPrompt,
                systemPrompt: systemPrompt
            )
        }

        guard ChatViewModel.hasCloudConsent(for: config.type) else {
            throw LLMError.requestFailed("Enable cloud data sharing consent for the current model before translating notes.")
        }

        let credential = try await settingsVM.resolvedCredential(for: config)
        let service = LLMService(config: config, apiKey: credential)
        return try await service.completeChat(messages: [
            (role: "system", content: systemPrompt),
            (role: "user", content: userPrompt)
        ])
    }

    private func decodeTranslation(from raw: String) throws -> JournalTranslationResponse {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = extractJSONObject(from: trimmed)
        guard let data = candidate.data(using: .utf8) else {
            throw LLMError.invalidResponse
        }

        do {
            let json = try JSONSerialization.jsonObject(with: data)
            return try parseTranslation(json)
        } catch {
            throw LLMError.requestFailed(
                "The translation response was not in a readable format. Try a different model or try again."
            )
        }
    }

    private func extractJSONObject(from raw: String) -> String {
        let withoutCodeFences = raw
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = withoutCodeFences.firstIndex(of: "{"),
           let end = withoutCodeFences.lastIndex(of: "}") {
            return String(withoutCodeFences[start...end])
        }
        return withoutCodeFences
    }

    private func parseTranslation(_ json: Any) throws -> JournalTranslationResponse {
        guard let dictionary = json as? [String: Any] else {
            throw LLMError.invalidResponse
        }

        return JournalTranslationResponse(
            summary: parseOptionalString(dictionary["summary"]),
            details: parseOptionalString(dictionary["details"]),
            notes: parseOptionalNotes(dictionary["notes"])
        )
    }

    private func parseOptionalString(_ value: Any?) -> String? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let string = value as? String {
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let array = value as? [Any] {
            let joined = array.compactMap { parseOptionalString($0) }.joined(separator: "\n")
            return joined.isEmpty ? nil : joined
        }
        return String(describing: value)
    }

    private func parseOptionalNotes(_ value: Any?) -> [String]? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        if let notes = value as? [String] {
            let cleaned = notes
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let notes = value as? [Any] {
            let cleaned = notes
                .compactMap { parseOptionalString($0) }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return cleaned.isEmpty ? nil : cleaned
        }
        if let single = parseOptionalString(value) {
            let split = single
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .map { $0.replacingOccurrences(of: #"^[-•*]\s*"#, with: "", options: .regularExpression) }
                .filter { !$0.isEmpty }
            return split.isEmpty ? [single] : split
        }
        return nil
    }

    private func save() {
        guard let currentProfileID else { return }
        let encodedTranslations = translationsByEntry.reduce(into: [String: [String: JournalEntryTranslation]]()) { partial, item in
            partial[item.key] = item.value.reduce(into: [String: JournalEntryTranslation]()) { inner, languageItem in
                inner[languageItem.key.rawValue] = languageItem.value
            }
        }

        EncryptedStore.save(
            JournalTranslationPayload(
                translations: encodedTranslations,
                selectedLanguageRawValue: selectedLanguage?.rawValue
            ),
            forKey: storageKey(for: currentProfileID)
        )
    }

    private func storageKey(for profileID: UUID) -> String {
        "journal_translations_\(profileID.uuidString)"
    }

    static func isTranslatable(_ entry: EirEntry) -> Bool {
        let hasSummary = !(entry.content?.summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasDetails = !(entry.content?.details?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let hasNotes = !(entry.content?.notes?.joined().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        return hasSummary || hasDetails || hasNotes
    }
}
