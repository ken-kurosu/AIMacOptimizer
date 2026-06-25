import Foundation

// MARK: - AI Chat Models

/// A message in the AI chat conversation
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date

    init(role: ChatRole, content: String) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
    }
}

enum ChatRole: String, Codable {
    case user
    case assistant
    case system
}

/// AI API provider configuration
enum AIProvider: String, Codable, CaseIterable {
    case openAI = "OpenAI"
    case anthropic = "Anthropic"

    var displayName: String { rawValue }

    var defaultModel: String {
        switch self {
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-4-5-20251001"
        }
    }

    var apiEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        }
    }

    /// Approximate cost per 1K tokens (input)
    var costPer1KInput: String {
        switch self {
        case .openAI: return "$0.00015"
        case .anthropic: return "$0.0008"
        }
    }
}

/// Settings for the AI chat feature
struct AIChatSettings: Codable {
    var provider: AIProvider = .openAI
    var apiKey: String = ""
    var model: String = ""
    var maxTokens: Int = 1024

    var effectiveModel: String {
        model.isEmpty ? provider.defaultModel : model
    }

    var isConfigured: Bool {
        !apiKey.isEmpty
    }
}
