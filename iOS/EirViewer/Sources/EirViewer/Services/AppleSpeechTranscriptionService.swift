import Foundation
import AVFoundation
import Speech

@MainActor
struct AppleSpeechTranscriptionService {
    enum ServiceError: LocalizedError {
        case notAuthorized
        case recognizerUnavailable
        case transcriptionUnavailable

        var errorDescription: String? {
            switch self {
            case .notAuthorized:
                return "Apple Speech access was not allowed."
            case .recognizerUnavailable:
                return "Apple Speech is not available for this language on this device."
            case .transcriptionUnavailable:
                return "Apple Speech could not turn this voice note into text."
            }
        }
    }

    static func transcribe(
        url: URL,
        preferredLocaleIdentifier: String = "sv-SE"
    ) async throws -> String {
        let authorization = await requestAuthorization()
        guard authorization == .authorized else {
            throw ServiceError.notAuthorized
        }

        if #available(iOS 26.0, *),
           SpeechTranscriber.isAvailable,
           let transcript = try await transcribeWithSpeechTranscriber(
                url: url,
                preferredLocaleIdentifier: preferredLocaleIdentifier
           ) {
            return transcript
        }

        guard let recognizer = preferredRecognizer(for: preferredLocaleIdentifier) else {
            throw ServiceError.recognizerUnavailable
        }

        if recognizer.supportsOnDeviceRecognition {
            let request = makeRequest(for: url, requiresOnDeviceRecognition: true)
            if let transcript = try await recognize(using: recognizer, request: request) {
                return transcript
            }
        }

        let request = makeRequest(for: url, requiresOnDeviceRecognition: false)
        if let transcript = try await recognize(using: recognizer, request: request) {
            return transcript
        }

        throw ServiceError.transcriptionUnavailable
    }

    @available(iOS 26.0, *)
    private static func transcribeWithSpeechTranscriber(
        url: URL,
        preferredLocaleIdentifier: String
    ) async throws -> String? {
        let locale = await preferredTranscriberLocale(for: preferredLocaleIdentifier)
        let transcriber = SpeechTranscriber(locale: locale, preset: .transcription)
        let audioFile = try AVAudioFile(forReading: url)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        try await analyzer.prepareToAnalyze(in: audioFile.processingFormat)

        let collector = Task {
            var latestTranscript: String?
            for try await result in transcriber.results {
                let candidate = String(result.text.characters).trimmingCharacters(in: .whitespacesAndNewlines)
                if !candidate.isEmpty {
                    latestTranscript = candidate
                }
            }
            return latestTranscript
        }

        do {
            try await analyzer.start(inputAudioFile: audioFile, finishAfterFile: true)
            return try await collector.value
        } catch {
            collector.cancel()
            throw error
        }
    }

    private static func makeRequest(for url: URL, requiresOnDeviceRecognition: Bool) -> SFSpeechURLRecognitionRequest {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.taskHint = .dictation
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        if #available(iOS 16.0, *) {
            request.addsPunctuation = true
        }
        return request
    }

    @available(iOS 26.0, *)
    private static func preferredTranscriberLocale(for localeIdentifier: String) async -> Locale {
        let requested = Locale(identifier: localeIdentifier)
        let current = Locale.autoupdatingCurrent
        let supported = await SpeechTranscriber.supportedLocales

        if let exact = supported.first(where: { normalizedIdentifier($0.identifier) == normalizedIdentifier(requested.identifier) }) {
            return exact
        }

        if let currentExact = supported.first(where: { normalizedIdentifier($0.identifier) == normalizedIdentifier(current.identifier) }) {
            return currentExact
        }

        let requestedLanguage = normalizedLanguageCode(for: requested.identifier)
        if let requestedLanguage,
           let languageMatch = supported.first(where: { normalizedLanguageCode(for: $0.identifier) == requestedLanguage }) {
            return languageMatch
        }

        let currentLanguage = normalizedLanguageCode(for: current.identifier)
        if let currentLanguage,
           let languageMatch = supported.first(where: { normalizedLanguageCode(for: $0.identifier) == currentLanguage }) {
            return languageMatch
        }

        return requested
    }

    private static func preferredRecognizer(for localeIdentifier: String) -> SFSpeechRecognizer? {
        let requested = Locale(identifier: localeIdentifier)
        if let recognizer = SFSpeechRecognizer(locale: requested) {
            return recognizer
        }

        let current = Locale.autoupdatingCurrent
        if current.identifier != localeIdentifier,
           let recognizer = SFSpeechRecognizer(locale: current) {
            return recognizer
        }

        return SFSpeechRecognizer()
    }

    private static func recognize(
        using recognizer: SFSpeechRecognizer,
        request: SFSpeechURLRecognitionRequest
    ) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            var hasResumed = false
            var recognitionTask: SFSpeechRecognitionTask?

            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error, !hasResumed {
                    hasResumed = true
                    recognitionTask?.cancel()
                    continuation.resume(throwing: error)
                    return
                }

                guard let result, result.isFinal, !hasResumed else { return }
                hasResumed = true
                recognitionTask?.cancel()
                let transcript = result.bestTranscription.formattedString.trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: transcript.isEmpty ? nil : transcript)
            }
        }
    }

    private static func requestAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func normalizedIdentifier(_ identifier: String) -> String {
        identifier.replacingOccurrences(of: "_", with: "-").lowercased()
    }

    private static func normalizedLanguageCode(for identifier: String) -> String? {
        normalizedIdentifier(identifier).split(separator: "-").first.map(String.init)
    }
}
