import Foundation
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
}
