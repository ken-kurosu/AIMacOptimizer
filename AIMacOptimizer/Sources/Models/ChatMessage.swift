import Foundation

// MARK: - AI Chat Models

/// A message in the AI chat conversation
struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: ChatRole
    let content: String
    let timestamp: Date
    /// このメッセージに紐づく実行可能アクション（削除提案など）
    var actions: [ChatActionDescriptor]

    init(role: ChatRole, content: String, actions: [ChatActionDescriptor] = []) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.actions = actions
    }
}

/// チャットから実行できるアクションの種類
enum ChatActionType: String, Codable {
    case deleteCacheSafe   // キャッシュ/ログの安全削除
    case moveToTrash       // ゴミ箱へ移動（要確認のファイル）
    case openURL           // 外部リンクを開く（おすすめ商品など）
}

/// チャットメッセージに添える「実行できる操作」の記述（ボタン化される）
struct ChatActionDescriptor: Identifiable, Codable {
    var id = UUID()
    let label: String       // ボタン文言（例: "キャッシュを削除 (4.8GB)"）
    let type: ChatActionType
    let path: String        // 対象パス
    let sizeMB: Double
    let risk: String        // "安全" / "やや注意"
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

    /// Localized display name (rawValue kept stable for Codable)
    var displayName: String {
        switch self {
        case .local: return L10n.providerLocal
        case .appleOnDevice: return L10n.providerAppleOnDevice
        }
    }

    /// 有料API相談モードは廃止。全プロバイダが無料・キー不要・ランニングコスト0。
    var requiresAPIKey: Bool { false }
    var isFree: Bool { true }

    var defaultModel: String {
        switch self {
        case .local: return "rule-engine"
        case .appleOnDevice: return "apple-on-device"
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
