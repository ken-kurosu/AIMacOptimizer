import Foundation
import UserNotifications

// MARK: - Models

/// 削除の安全度
enum CleanupSafety: String, Codable {
    case safe = "安全"
    case caution = "やや注意"

    /// バッジ表示用の色名（UI 側で Color にマッピング）
    var colorName: String {
        switch self {
        case .safe: return "green"
        case .caution: return "orange"
        }
    }

    var icon: String {
        switch self {
        case .safe: return "checkmark.shield.fill"
        case .caution: return "exclamationmark.triangle.fill"
        }
    }
}

/// 自動回避で削除する候補 1 件
struct CleanupCandidate: Identifiable {
    let id = UUID()
    let name: String
    let path: String
    let sizeMB: Double
    let safety: CleanupSafety
    /// 「なぜ消して安全か」の説明
    let reason: String

    var sizeFormatted: String {
        sizeMB >= 1024 ? String(format: "%.1f GB", sizeMB / 1024) : String(format: "%.0f MB", sizeMB)
    }
}

/// ストレージ圧迫時に提示する「安全に空ける」プラン
struct SafeCleanupPlan {
    let candidates: [CleanupCandidate]
    let usagePercentBefore: Double
    let freeGBBefore: Double

    var totalMB: Double { candidates.reduce(0) { $0 + $1.sizeMB } }
    var totalFormatted: String {
        totalMB >= 1024 ? String(format: "%.1f GB", totalMB / 1024) : String(format: "%.0f MB", totalMB)
    }
    var isEmpty: Bool { candidates.isEmpty }
}

/// ストレージ自動ガードの設定（UserDefaults に JSON 永続化）
struct DiskGuardSettings: Codable {
    /// 定期監視を行うか
    var enabled: Bool = true
    /// 圧迫検知時に承認なしで自動削除するか（その場合は通知のみ）
    var autoClean: Bool = false
    /// 使用率がこの値(%)以上で「圧迫」とみなす
    var thresholdPercent: Double = 90
    /// 空き容量がこの値(GB)未満で「圧迫」とみなす
    var minFreeGB: Double = 10
}

// MARK: - DiskGuard

/// ディスク使用状況を定期監視し、圧迫時に「リスクのないキャッシュ/ログ」の
/// 安全な削除を提案（または承認済みなら自動実行）するサービス。
@MainActor
final class DiskGuard: ObservableObject {
    static let shared = DiskGuard()

    /// UI に提示中の提案（手動モードで圧迫検知した時にセット）
    @Published private(set) var pendingPlan: SafeCleanupPlan?
    /// 設定（変更すると自動で永続化）
    @Published var settings: DiskGuardSettings {
        didSet { saveSettings() }
    }
    /// 直近の自動削除サマリ（UI で軽く表示する用、任意）
    @Published private(set) var lastAutoCleanSummary: String?

    private let analyzer = StorageAnalyzer()
    private let defaults = UserDefaults.standard
    private let settingsKey = "diskGuardSettings"
    private let lastActionKey = "diskGuardLastActionTimestamp"
    /// 同じ圧迫で何度も提案/削除しないためのクールダウン（3 時間）
    private let cooldown: TimeInterval = 3 * 60 * 60

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(DiskGuardSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = DiskGuardSettings()
        }
    }

    // MARK: - 監視

    /// AppDelegate の定期タイマーから呼ぶ。圧迫を検知したら提案/自動削除する。
    func evaluate() {
        guard settings.enabled else { return }

        let info = analyzer.getStorageInfo()
        guard info.totalGB > 0 else { return }

        let pressured = info.usagePercent >= settings.thresholdPercent || info.freeGB < settings.minFreeGB
        guard pressured else { return }

        // すでに提案を出しているなら重複させない
        guard pendingPlan == nil else { return }
        // クールダウン中はスキップ
        guard cooldownElapsed else { return }

        // 安全候補（キャッシュ/ログのみ・フォント等の保護対象は除外）を収集
        let candidates = buildCandidates()
        guard !candidates.isEmpty else { return }

        let plan = SafeCleanupPlan(
            candidates: candidates,
            usagePercentBefore: info.usagePercent,
            freeGBBefore: info.freeGB
        )

        if settings.autoClean {
            // 承認済み → 自動で空けて通知のみ
            performCleanup(plan, auto: true)
        } else {
            // 手動 → 提案を UI に出し、気付けるよう通知
            pendingPlan = plan
            notify(
                title: "ストレージ圧迫を検知しました",
                body: "安全に空けられる項目が約\(plan.totalFormatted)あります。アプリを開いて確認してください。"
            )
        }
    }

    // MARK: - 操作（UI から）

    /// 提案を承認して実行。`enableAutoFromNow` が true なら今後は自動削除に切り替える。
    func approvePendingPlan(enableAutoFromNow: Bool) {
        guard let plan = pendingPlan else { return }
        if enableAutoFromNow { settings.autoClean = true }
        performCleanup(plan, auto: false)
        pendingPlan = nil
    }

    /// 提案を却下（今回は何もしない）。
    func dismissPendingPlan() {
        pendingPlan = nil
        markActionTaken() // クールダウンを効かせ、すぐ再提案しない
    }

    // MARK: - 実行

    private func performCleanup(_ plan: SafeCleanupPlan, auto: Bool) {
        let analyzer = self.analyzer
        // ファイル IO は重いのでバックグラウンドで実行
        Task.detached {
            var freedMB: Double = 0
            var cleared = 0
            for candidate in plan.candidates {
                let item = StorageItem(
                    path: candidate.path,
                    name: candidate.name,
                    sizeMB: candidate.sizeMB,
                    category: .cache,
                    isDirectory: true
                )
                // スキャン時の満額ではなく、実際に減った容量を加算する（過大表示を防ぐ）
                let actuallyFreed = analyzer.clearCacheMeasuringFreed(item)
                if actuallyFreed > 0 {
                    freedMB += actuallyFreed
                    cleared += 1
                }
            }
            await self.finishCleanup(cleared: cleared, freedMB: freedMB, auto: auto)
        }
    }

    private func finishCleanup(cleared: Int, freedMB: Double, auto: Bool) {
        markActionTaken()
        let freedText = freedMB >= 1024 ? String(format: "%.1f GB", freedMB / 1024) : String(format: "%.0f MB", freedMB)
        let summary = "\(cleared)項目のキャッシュ/ログを削除し、約\(freedText)を確保しました。"
        lastAutoCleanSummary = summary

        // 自動・手動どちらでも完了通知を出す（自動モードでは通知のみが唯一の通知手段）
        notify(
            title: auto ? "ストレージを自動で空けました" : "ストレージを空けました",
            body: summary
        )
    }

    // MARK: - 候補生成

    private func buildCandidates() -> [CleanupCandidate] {
        analyzer.findSafeCleanupItems().map { item in
            let reason: String
            let safety: CleanupSafety = .safe
            switch item.category {
            case .log:
                reason = "過去のログ。削除しても自動で再生成され、動作に影響しません。"
            default:
                reason = "アプリが自動で再生成するキャッシュ。削除しても動作に影響しません。"
            }
            return CleanupCandidate(
                name: item.name,
                path: item.path,
                sizeMB: item.sizeMB,
                safety: safety,
                reason: reason
            )
        }
    }

    // MARK: - クールダウン

    private var cooldownElapsed: Bool {
        guard let last = defaults.object(forKey: lastActionKey) as? TimeInterval else { return true }
        return Date().timeIntervalSince1970 - last >= cooldown
    }

    private func markActionTaken() {
        defaults.set(Date().timeIntervalSince1970, forKey: lastActionKey)
    }

    // MARK: - 永続化・通知

    private func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        defaults.set(data, forKey: settingsKey)
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
