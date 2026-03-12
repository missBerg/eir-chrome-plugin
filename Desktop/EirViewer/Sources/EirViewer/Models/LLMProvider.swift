import Foundation

enum LLMProviderType: String, CaseIterable, Identifiable, Codable {
    case bergetTrial = "Berget AI Trial"
    case openai = "OpenAI"
    case anthropic = "Anthropic"
    case minimax = "MiniMax"
    case groq = "Groq"
    case custom = "Custom"
    case local = "On-Device"

    var id: String { rawValue }

    var isLocal: Bool { self == .local }

    var defaultBaseURL: String {
        switch self {
        case .bergetTrial: return "https://scribe.eir.space/v1"
        case .openai: return "https://api.openai.com/v1"
        case .anthropic: return "https://api.anthropic.com/v1"
        case .minimax: return "https://api.minimax.io/anthropic/v1"
        case .groq: return "https://api.groq.com/openai/v1"
        case .custom: return ""
        case .local: return ""
        }
    }

    var defaultModel: String {
        switch self {
        case .bergetTrial: return "openai/gpt-oss-120b"
        case .openai: return "gpt-4.1"
        case .anthropic: return "claude-sonnet-4-5-20250929"
        case .minimax: return "MiniMax-M1"
        case .groq: return "llama-3.3-70b-versatile"
        case .custom: return ""
        case .local: return ""
        }
    }

    var usesOpenAICompat: Bool {
        switch self {
        case .bergetTrial, .openai, .groq, .custom: return true
        case .anthropic, .minimax: return false
        case .local: return false
        }
    }

    var requiresUserAPIKey: Bool {
        switch self {
        case .bergetTrial, .local:
            return false
        case .openai, .anthropic, .minimax, .groq, .custom:
            return true
        }
    }

    var usesManagedTrialAccess: Bool { self == .bergetTrial }

    var storageSlug: String {
        switch self {
        case .bergetTrial: return "berget_trial"
        case .openai: return "openai"
        case .anthropic: return "anthropic"
        case .minimax: return "minimax"
        case .groq: return "groq"
        case .custom: return "custom"
        case .local: return "local"
        }
    }
}

struct LLMProviderConfig: Codable, Identifiable {
    var id: String { type.rawValue }
    var type: LLMProviderType
    var baseURL: String
    var model: String
    var isEnabled: Bool

    init(type: LLMProviderType) {
        self.type = type
        self.baseURL = type.defaultBaseURL
        self.model = type.defaultModel
        self.isEnabled = false
    }
}
