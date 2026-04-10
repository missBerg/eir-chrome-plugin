import Foundation

@MainActor
struct VoiceTranscriptionCoordinator {
    enum Context {
        case chat
        case stateNote
        case careIntake

        var polishFocus: String {
            switch self {
            case .chat:
                return "This transcript will be sent as a health chat message."
            case .stateNote:
                return "This transcript will be saved as a short state check-in note."
            case .careIntake:
                return "This transcript will be used to describe a care need to the app."
            }
        }
    }

    static func transcribe(
        draft: RecordedVoiceNoteDraft,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager? = nil,
        preferredLocaleIdentifier: String = Locale.autoupdatingCurrent.identifier,
        context: Context
    ) async throws -> String {
        let preferredLocale = normalizedPreferredLocaleIdentifier(from: preferredLocaleIdentifier)

        do {
            let transcript = try await AppleSpeechTranscriptionService.transcribe(
                url: draft.fileURL,
                preferredLocaleIdentifier: preferredLocale
            )
            return await polishIfNeeded(
                transcript: transcript,
                context: context,
                preferredLocaleIdentifier: preferredLocale,
                settingsVM: settingsVM,
                localModelManager: localModelManager
            )
        } catch {
            if let hostedTranscript = try await hostedFallbackTranscriptIfAllowed(
                draft: draft,
                settingsVM: settingsVM
            ) {
                return await polishIfNeeded(
                    transcript: hostedTranscript,
                    context: context,
                    preferredLocaleIdentifier: preferredLocale,
                    settingsVM: settingsVM,
                    localModelManager: localModelManager
                )
            }
            throw error
        }
    }

    private static func hostedFallbackTranscriptIfAllowed(
        draft: RecordedVoiceNoteDraft,
        settingsVM: SettingsViewModel
    ) async throws -> String? {
        guard let config = settingsVM.activeProvider,
              config.type.usesManagedTrialAccess,
              hasCloudConsent(for: config.type) else {
            return nil
        }

        let transcript = try await VoiceNoteTranscriptionService.transcribe(draft: draft, settingsVM: settingsVM)
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func polishIfNeeded(
        transcript: String,
        context: Context,
        preferredLocaleIdentifier: String,
        settingsVM: SettingsViewModel,
        localModelManager: LocalModelManager?
    ) async -> String {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        guard settingsVM.voiceTranscriptPolishEnabled else { return trimmed }
        guard let localModelManager else { return trimmed }

        let shouldTryLocalPolish = settingsVM.activeProviderType.isLocal || localModelManager.isReady
        guard shouldTryLocalPolish else { return trimmed }

        do {
            if !localModelManager.isReady {
                try await localModelManager.ensurePreferredModelLoaded()
            }

            let polished = try await localModelManager.service.completeDetachedResponse(
                userMessage: polishUserPrompt(
                    transcript: trimmed,
                    context: context
                ),
                systemPrompt: polishSystemPrompt(
                    preferredLocaleIdentifier: preferredLocaleIdentifier
                )
            )

            return sanitizePolishedTranscript(polished, fallback: trimmed)
        } catch {
            return trimmed
        }
    }

    private static func polishSystemPrompt(preferredLocaleIdentifier: String) -> String {
        """
        You clean up raw speech-to-text transcripts for a health app.

        Rules:
        - Return only the corrected transcript.
        - Keep the same language as the original transcript.
        - Preserve meaning exactly.
        - Fix casing, punctuation, spacing, and only very likely recognition mistakes.
        - Do not add headings, quotes, explanations, summaries, or advice.
        - Do not invent symptoms, medications, diagnoses, or details.
        - If something is uncertain, keep the original wording.

        Preferred locale: \(preferredLocaleIdentifier)
        """
    }

    private static func polishUserPrompt(
        transcript: String,
        context: Context
    ) -> String {
        """
        \(context.polishFocus)

        Clean up this raw transcript conservatively and return only the corrected transcript:

        \(transcript)
        """
    }

    private static func sanitizePolishedTranscript(_ polished: String, fallback: String) -> String {
        var cleaned = polished.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return fallback }

        if cleaned.hasPrefix("```") {
            cleaned = cleaned
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let lowercased = cleaned.lowercased()
        let removablePrefixes = [
            "corrected transcript:",
            "corrected:",
            "transcript:"
        ]
        if let prefix = removablePrefixes.first(where: { lowercased.hasPrefix($0) }) {
            cleaned = String(cleaned.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: "\""))

        if cleaned.isEmpty || cleaned.count > max(fallback.count * 3, 3200) {
            return fallback
        }

        return cleaned
    }

    private static func hasCloudConsent(for provider: LLMProviderType) -> Bool {
        UserDefaults.standard.bool(forKey: "cloudConsent_\(provider.rawValue)")
    }

    private static func normalizedPreferredLocaleIdentifier(from identifier: String) -> String {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "und" {
            return "sv-SE"
        }
        return trimmed
    }
}
