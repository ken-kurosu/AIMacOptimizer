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

/// AI provider configuration（ローカル/オンデバイスは無料・キー不要、API系は上級モード）
enum AIProvider: String, Codable, CaseIterable {
    /// ルール/テンプレートによるローカル解析（無料・キー不要・オフライン）
    case local = "ローカル解析（無料）"
    /// Apple オンデバイスLLM（無料・キー不要、対応OS/チップのみ）
    case appleOnDevice = "オンデバイスAI（無料）"
    case openAI = "OpenAI（要APIキー）"
    case anthropic = "Anthropic（要APIキー）"

    var displayName: String { rawValue }

    /// APIキーが必要か（=ランニングコストが発生しうる上級モード）
    var requiresAPIKey: Bool {
        switch self {
        case .local, .appleOnDevice: return false
        case .openAI, .anthropic: return true
        }
    }

    /// ランニングコストが一切かからない無料プロバイダか
    var isFree: Bool { !requiresAPIKey }

    var defaultModel: String {
        switch self {
        case .local: return "rule-engine"
        case .appleOnDevice: return "apple-on-device"
        case .openAI: return "gpt-4o-mini"
        case .anthropic: return "claude-haiku-4-5-20251001"
        }
    }

    var apiEndpoint: String {
        switch self {
        case .openAI: return "https://api.openai.com/v1/chat/completions"
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .local, .appleOnDevice: return ""
        }
    }

    /// Approximate cost per 1K tokens (input)
    var costPer1KInput: String {
        switch self {
        case .local, .appleOnDevice: return "無料"
        case .openAI: return "$0.00015"
        case .anthropic: return "$0.0008"
        }
    }
}

/// Settings for the AI chat feature
struct AIChatSettings: Codable {
    var provider: AIProvider = .local
    var apiKey: String = ""
    var model: String = ""
    var maxTokens: Int = 1024

    var effectiveModel: String {
        model.isEmpty ? provider.defaultModel : model
    }

    /// チャットが利用可能か（無料プロバイダは常に可。API系はキー必須）
    var isConfigured: Bool {
        provider.requiresAPIKey ? !apiKey.isEmpty : true
    }
}
