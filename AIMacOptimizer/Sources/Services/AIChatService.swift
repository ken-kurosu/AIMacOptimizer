import Foundation

/// AI Chat Service — connects to OpenAI or Anthropic API using user's own API key
/// Cost-conscious: uses GPT-4o-mini by default ($0.15/1M input tokens)
@MainActor
final class AIChatService: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var settings: AIChatSettings

    /// The diagnosis report to inject as context
    private var diagnosisContext: String = ""
    /// 構造化された診断レポート（ローカル解析エンジンが実測値に基づき回答するのに使う）
    private var diagnosisReport: DiagnosisReport?

    // Persistence keys
    private let providerKey = "ai_chat_provider"
    private let apiKeyKey = "ai_chat_api_key"
    private let modelKey = "ai_chat_model"

    init() {
        // Load saved settings
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .openAI
        let apiKey = AIChatService.loadAPIKey()
        let model = UserDefaults.standard.string(forKey: modelKey) ?? ""

        self.settings = AIChatSettings(provider: provider, apiKey: apiKey, model: model)
    }

    // MARK: - API Key Management (Keychain-backed)

    private static let keychainService = "com.aimacoptimizer.apikey"

    private static func loadAPIKey() -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return ""
    }

    func saveSettings() {
        UserDefaults.standard.set(settings.provider.rawValue, forKey: providerKey)
        UserDefaults.standard.set(settings.model, forKey: modelKey)

        // Save API key to Keychain
        let keyData = settings.apiKey.data(using: .utf8)!
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AIChatService.keychainService,
        ]
        SecItemDelete(query as CFDictionary) // Remove existing
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: AIChatService.keychainService,
            kSecValueData as String: keyData
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    // MARK: - Context Injection

    /// Set the diagnosis report as context for the AI chat
    func setDiagnosisContext(_ report: DiagnosisReport) {
        diagnosisContext = report.contextSummary()
        diagnosisReport = report
    }

    // MARK: - System Prompt

    private var systemPrompt: String {
        """
        あなたはMac最適化の専門AIアシスタントです。ユーザーのMacの状態を診断レポートに基づいて分析し、具体的で実行可能なアドバイスを提供します。

        ルール:
        - 日本語で回答してください
        - 診断レポートのデータに基づいて具体的に回答してください
        - 安全でないコマンドを推奨しないでください
        - 操作手順は分かりやすく段階的に説明してください
        - 専門的すぎる用語には簡単な説明を添えてください
        - ユーザーのスキルレベルに合わせて回答を調整してください

        以下はユーザーのMacの最新診断レポートです:

        \(diagnosisContext.isEmpty ? "（診断レポートはまだありません。先にDeep Diagnosisを実行してください）" : diagnosisContext)
        """
    }

    // MARK: - Send Message

    func sendMessage(_ content: String) async {
        let userMessage = ChatMessage(role: .user, content: content)
        messages.append(userMessage)
        isLoading = true
        errorMessage = nil

        // API系プロバイダのみキーが必要。ローカル/オンデバイスはキー不要で常に利用可。
        guard settings.isConfigured else {
            errorMessage = "APIキーが設定されていません。設定画面からAPIキーを入力するか、無料の『ローカル解析』に切り替えてください。"
            isLoading = false
            return
        }

        do {
            let response: String
            switch settings.provider {
            case .local:
                response = LocalAdvisor.shared.answer(question: content, report: diagnosisReport)
            case .appleOnDevice:
                // オンデバイスLLMが使えればそれを、ダメならローカル解析にフォールバック
                if let r = await AppleIntelligence.respond(system: systemPrompt, prompt: content) {
                    response = r
                } else {
                    response = LocalAdvisor.shared.answer(question: content, report: diagnosisReport)
                }
            case .openAI:
                response = try await callOpenAI(messages: messages)
            case .anthropic:
                response = try await callAnthropic(messages: messages)
            }

            let assistantMessage = ChatMessage(role: .assistant, content: response)
            messages.append(assistantMessage)
        } catch {
            errorMessage = "エラー: \(error.localizedDescription)"
        }

        isLoading = false
    }

    /// Clear conversation
    func clearChat() {
        messages.removeAll()
        errorMessage = nil
    }

    // MARK: - OpenAI API

    private func callOpenAI(messages: [ChatMessage]) async throws -> String {
        let url = URL(string: settings.provider.apiEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(settings.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = [
            ["role": "system", "content": systemPrompt]
        ]
        for msg in messages where msg.role != .system {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": settings.effectiveModel,
            "messages": apiMessages,
            "max_tokens": settings.maxTokens,
            "temperature": 0.7
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw ChatError.invalidAPIKey
            }
            throw ChatError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let firstChoice = choices.first,
              let message = firstChoice["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw ChatError.invalidResponse
        }

        return content
    }

    // MARK: - Anthropic API

    private func callAnthropic(messages: [ChatMessage]) async throws -> String {
        let url = URL(string: settings.provider.apiEndpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(settings.apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var apiMessages: [[String: String]] = []
        for msg in messages where msg.role != .system {
            apiMessages.append(["role": msg.role.rawValue, "content": msg.content])
        }

        let body: [String: Any] = [
            "model": settings.effectiveModel,
            "system": systemPrompt,
            "messages": apiMessages,
            "max_tokens": settings.maxTokens
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ChatError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            if httpResponse.statusCode == 401 {
                throw ChatError.invalidAPIKey
            }
            throw ChatError.apiError(statusCode: httpResponse.statusCode, message: errorBody)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let firstContent = contentArray.first,
              let text = firstContent["text"] as? String else {
            throw ChatError.invalidResponse
        }

        return text
    }
}

// MARK: - Chat Errors

enum ChatError: LocalizedError {
    case invalidAPIKey
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidAPIKey:
            return "APIキーが無効です。設定で正しいキーを入力してください。"
        case .invalidResponse:
            return "AIからの応答を解析できませんでした。"
        case .apiError(let code, let msg):
            return "API エラー (\(code)): \(msg)"
        }
    }
}
