import Foundation
import UserNotifications

/// 定期最適化レポート — "使い続けるほど効く"継続価値の中核。
///
/// 「何が容量を食っているか(大物Top)」「空き/メモリ/Swap のトレンド」「快適に使うための助言」を
/// 週次でまとめ、通知（＋アプリ内で参照）する。過大表示はせず、実測値と履歴だけを根拠にする。
/// 既存の監視タイマーに相乗りし、軽さを損なわない設計（重い I/O はバックグラウンドへ逃がす）。
@MainActor
final class WeeklyReportService {
    static let shared = WeeklyReportService()

    /// 生成済みレポート（アプリ内表示・通知の両方に使う）
    struct Summary: Sendable {
        var title: String
        var subtitle: String
        var notificationBody: String
        var lines: [String]        // アプリ内で一覧表示するための詳細行
        var generatedAt: Date
    }

    private let defaults = UserDefaults.standard
    private let enabledKey = "weeklyReportEnabled"
    private let lastSentKey = "weeklyReportLastSent"
    private let intervalSec: TimeInterval = 7 * 24 * 60 * 60

    private(set) var lastReport: Summary?
    private var isBuilding = false

    private init() {
        if defaults.object(forKey: enabledKey) == nil {
            defaults.set(true, forKey: enabledKey)
        }
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: enabledKey) == nil ? true : defaults.bool(forKey: enabledKey) }
        set { defaults.set(newValue, forKey: enabledKey) }
    }

    /// 監視タイマーから定期的に呼ぶ。7日経過していればレポートを生成して通知する。
    /// インストール直後の「空レポート」を避けるため、初回は基準日だけ置いて1週間後から送る。
    func checkAndSendIfDue() {
        guard isEnabled else { return }
        guard let last = defaults.object(forKey: lastSentKey) as? Date else {
            defaults.set(Date(), forKey: lastSentKey)
            return
        }
        guard Date().timeIntervalSince(last) >= intervalSec else { return }
        Task { await generateAndSend() }
    }

    /// 手動生成（設定の「今すぐレポートを確認」用）。生成すると通知も送る。
    @discardableResult
    func generateNow() async -> Summary {
        let s = await buildReport()
        lastReport = s
        NotificationService.shared.sendReport(title: s.title, body: s.notificationBody, subtitle: s.subtitle)
        return s
    }

    private func generateAndSend() async {
        if isBuilding { return }
        isBuilding = true
        defer { isBuilding = false }
        let s = await buildReport()
        lastReport = s
        defaults.set(Date(), forKey: lastSentKey)
        NotificationService.shared.sendReport(title: s.title, body: s.notificationBody, subtitle: s.subtitle)
    }

    // MARK: - Report building

    private func buildReport() async -> Summary {
        // 大きい整理候補 Top3（安全に整理できるキャッシュ/ログのみ）。ファイル I/O はバックグラウンドへ。
        let top: [(name: String, sizeMB: Double)] = await Task.detached(priority: .utility) {
            StorageAnalyzer().findSafeCleanupItems()
                .prefix(3)
                .map { (name: $0.name, sizeMB: $0.sizeMB) }
        }.value

        // 現在の空き容量（10進・Finder 準拠）
        let storage = StorageAnalyzer().getStorageInfo()

        // 直近7日のトレンド（HealthHistory を再利用）
        let recent = HealthHistory.shared.recent(hours: 24 * 7)
        let avgMem = recent.isEmpty ? 0 : recent.map { $0.memUsedPercent }.reduce(0, +) / Double(recent.count)
        let avgSwap = recent.isEmpty ? 0 : recent.map { $0.swapMB }.reduce(0, +) / Double(recent.count)

        var freeTrendText = ""
        if recent.count >= 2, let first = recent.first, let latest = recent.last {
            let delta = latest.diskFreePercent - first.diskFreePercent
            if abs(delta) >= 1 {
                freeTrendText = String(format: "この1週間で空きが %@ %.0fpt", delta < 0 ? "減少" : "増加", abs(delta))
            }
        }

        // アプリ内表示用の詳細行
        var lines: [String] = []
        lines.append(String(format: "空き容量: %@ / %@（使用 %.0f%%）",
                            storage.freeFormatted, storage.totalFormatted, storage.usagePercent))
        if !freeTrendText.isEmpty { lines.append(freeTrendText) }
        if !top.isEmpty {
            lines.append("大きい項目: " + top.map { "\($0.name) \(fmt($0.sizeMB))" }.joined(separator: " / "))
        }
        if !recent.isEmpty {
            lines.append(String(format: "メモリ使用 平均 %.0f%% ・ Swap 平均 %@", avgMem, fmt(avgSwap)))
        }

        let advice = makeAdvice(freeGB: storage.freeGB,
                                topMB: top.first?.sizeMB ?? 0,
                                avgSwap: avgSwap,
                                usagePercent: storage.usagePercent)
        lines.append("提案: " + advice)

        // 通知は要点だけに凝縮（最大の整理候補＋助言）
        var body = ""
        if let t = top.first { body = "最大の整理候補は \(t.name)（\(fmt(t.sizeMB))）。" }
        body += advice

        return Summary(
            title: "今週のMac最適化レポート",
            subtitle: String(format: "空き %@ ・ 使用 %.0f%%", storage.freeFormatted, storage.usagePercent),
            notificationBody: body,
            lines: lines,
            generatedAt: Date()
        )
    }

    /// 実測値・履歴だけを根拠にした、誇張のない助言を1文で返す。
    private func makeAdvice(freeGB: Double, topMB: Double, avgSwap: Double, usagePercent: Double) -> String {
        if freeGB < 15 {
            return "空きが少なめです。ストレージ分析から安全に整理すると快適になります。"
        }
        if topMB >= 2048 {
            return "大きなキャッシュが溜まっています。ストレージ分析でまとめて整理できます。"
        }
        if avgSwap >= 1500 {
            return "Swap が多めです。メモリ最適化や不要タブの整理が効果的です。"
        }
        if usagePercent >= 85 {
            return "ディスク使用率が高めです。定期的な整理をおすすめします。"
        }
        return "状態は良好です。この調子でメニューバーからいつでも最適化できます。"
    }

    private func fmt(_ mb: Double) -> String {
        mb >= 1024 ? String(format: "%.1fGB", mb / 1024) : String(format: "%.0fMB", mb)
    }
}
