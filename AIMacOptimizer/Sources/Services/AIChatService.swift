import Foundation
import AppKit

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
        let provider = AIProvider(rawValue: UserDefaults.standard.string(forKey: providerKey) ?? "") ?? .local
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

        // ディスク/容量に関する質問は、実機をスキャンして
        // 「大きい順・リスク付き・その場で削除できる」具体的な助言を返す
        if isStorageQuestion(content) {
            let (text, actions) = await buildStorageAdvice()
            messages.append(ChatMessage(role: .assistant, content: text, actions: actions))
            isLoading = false
            return
        }

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
        }

        messages.append(ChatMessage(role: .assistant, content: response))
        isLoading = false
    }

    // MARK: - ディスク相談（実機スキャン＋実行アクション）

    private let storage = StorageAnalyzer()

    private func isStorageQuestion(_ q: String) -> Bool {
        let s = q.lowercased()
        let kw = ["ディスク", "容量", "空き", "ストレージ", "大き", "disk", "storage",
                  "空け", "削除", "消し", "消す", "掃除", "片付", "ファイル", "占有", "重い"]
        return kw.contains { s.contains($0) }
    }

    /// 実機をスキャンして「何が容量を食っているか（大きい順）」と削除アクションを組み立てる
    private func buildStorageAdvice() async -> (String, [ChatActionDescriptor]) {
        await storage.scan()
        let info = storage.getStorageInfo()
        let items = storage.items // 大きい順にソート済み

        var lines: [String] = []
        lines.append("このMacのストレージ状況")
        lines.append("空き \(info.freeFormatted) / 全体 \(info.totalFormatted)（使用 約\(Int(info.usagePercent))%）")
        lines.append("")

        guard !items.isEmpty else {
            lines.append("スキャンの結果、目立って大きい不要ファイルは見つかりませんでした。")
            lines.append("空きが少ない場合は、写真・動画・アプリ本体など個人ファイルの整理をご検討ください。")
            appendBoostText(&lines, info: info, safeFreeableMB: 0)
            return (lines.joined(separator: "\n"), [storageBoostAction()])
        }

        lines.append("容量を使っている項目（大きい順）と安全度")
        var actions: [ChatActionDescriptor] = []
        var safeFreeableMB: Double = 0
        for item in items.prefix(8) {
            let safe = (item.category == .cache || item.category == .log)
            let riskLabel = safe ? "安全" : "やや注意"
            let mark = safe ? "✅" : "⚠️"
            let reason = safe
                ? "再生成されるキャッシュ/ログ。削除して問題ありません"
                : "個人ファイルの可能性。中身を確認してから削除してください"
            lines.append("\(mark) \(item.name)　\(item.sizeFormatted)（\(riskLabel)）")
            lines.append("　\(reason)")
            if safe { safeFreeableMB += item.sizeMB }

            actions.append(ChatActionDescriptor(
                label: safe ? "削除 \(item.sizeFormatted)（安全）" : "ゴミ箱へ \(item.sizeFormatted)（要確認）",
                type: safe ? .deleteCacheSafe : .moveToTrash,
                path: item.path,
                sizeMB: item.sizeMB,
                risk: riskLabel
            ))
        }
        lines.append("")
        lines.append("下のボタンから、その場で削除できます。「安全」は消しても支障ありません。「要確認」は個人ファイルの可能性があるため、中身をご確認のうえ実行してください。")
        appendBoostText(&lines, info: info, safeFreeableMB: safeFreeableMB)
        // 容量を増やす方法（おすすめリンク）を常に最後に添える
        actions.append(storageBoostAction())
        return (lines.joined(separator: "\n"), actions)
    }

    /// 削除で空けきれない見込みのときだけ、補足テキストを添える
    private func appendBoostText(_ lines: inout [String], info: StorageInfo, safeFreeableMB: Double) {
        let projectedFreeGB = info.freeGB + safeFreeableMB / 1024
        guard projectedFreeGB < 20 else { return }
        lines.append("")
        lines.append("――――――")
        lines.append("これだけでは空きが足りない見込みです（削除しても約\(String(format: "%.0f", projectedFreeGB))GB）。内蔵を軽くするなら、写真・動画・古い資料を外付けに退避するのが手軽です。")
    }

    /// 「ストレージ容量を増やす方法」を開くアクション（おすすめ商品ページ）
    private func storageBoostAction() -> ChatActionDescriptor {
        let url = AffiliateManager.amazonSearch("%E5%A4%96%E4%BB%98%E3%81%91SSD")
        return ChatActionDescriptor(
            label: "ストレージ容量を増やす方法を見る",
            type: .openURL,
            path: url,
            sizeMB: 0,
            risk: "リンク"
        )
    }

    /// チャット上のアクション（削除/ゴミ箱/リンク）を実行し、結果メッセージを追加する
    func performChatAction(_ action: ChatActionDescriptor) async {
        // リンクを開くアクション（おすすめ商品など）は別処理
        if action.type == .openURL {
            if let url = URL(string: action.path) {
                NSWorkspace.shared.open(url)
            }
            return
        }

        let item = StorageItem(
            path: action.path,
            name: (action.path as NSString).lastPathComponent,
            sizeMB: action.sizeMB,
            category: action.type == .deleteCacheSafe ? .cache : .largeFile,
            isDirectory: true
        )
        let name = (action.path as NSString).lastPathComponent
        func fmt(_ mb: Double) -> String { mb >= 1024 ? String(format: "%.1f GB", mb / 1024) : String(format: "%.0f MB", mb) }

        let msg: String
        switch action.type {
        case .deleteCacheSafe:
            // スキャン満額ではなく「実際に減ったディスク容量」を表示する（保護スキップ/ロックで残った分は含めない）
            let freed = storage.clearCacheMeasuringFreed(item)
            msg = freed > 0
                ? "「\(name)」のキャッシュを削除しました（実測 約\(fmt(freed)) 解放）。"
                : "「\(name)」は削除できるものがありませんでした（使用中/フォント保護でスキップ）。"
        case .moveToTrash:
            // ゴミ箱移動はディスクを空けない。「解放」と言わず、事実を伝える
            let ok = storage.moveToTrash(item)
            msg = ok
                ? "「\(name)」をゴミ箱へ移動しました（約\(fmt(action.sizeMB))）。ゴミ箱を空にすると実際に空き容量が増えます。"
                : "「\(name)」の移動に失敗しました。使用中/権限の都合でスキップされた可能性があります。"
        case .openURL:
            msg = "「\(name)」の処理に失敗しました。"
        }
        messages.append(ChatMessage(role: .assistant, content: msg))
    }

    /// Clear conversation
    func clearChat() {
        messages.removeAll()
        errorMessage = nil
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
