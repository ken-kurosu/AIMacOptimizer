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

    /// Localized display name (rawValue kept stable for Codable)
    var localizedName: String {
        switch self {
        case .safe: return L10n.cleanupSafetySafe
        case .caution: return L10n.cleanupSafetyCaution
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

/// ストレージ圧迫の段階。空きが減るほど強く介入する（0バイト到達＝OS/他アプリが壊れる前に手を打つ）。
enum DiskPressureLevel: Int, Comparable {
    case normal = 0     // 余裕あり
    case notice          // 注意（早めの気づき）
    case critical        // 危険（強めに通知）
    case emergency       // 緊急（設定に関わらずリスク0を自動解放）

    static func < (a: DiskPressureLevel, b: DiskPressureLevel) -> Bool { a.rawValue < b.rawValue }
}

/// ストレージ自動ガードの設定（UserDefaults に JSON 永続化）
struct DiskGuardSettings: Codable {
    /// 定期監視を行うか
    var enabled: Bool = true
    /// 圧迫検知時に承認なしで自動削除するか（その場合は通知のみ）
    var autoClean: Bool = false
    /// 使用率がこの値(%)以上で「圧迫」とみなす
    var thresholdPercent: Double = 90
    /// 空き容量がこの値(GB)未満で「注意」とみなす
    var minFreeGB: Double = 10
    /// 空き容量がこの値(GB)未満で「危険」とみなす
    var criticalFreeGB: Double = 5
    /// 空き容量がこの値(GB)未満で「緊急」とみなす
    var emergencyFreeGB: Double = 2

    init() {}

    // 旧バージョンの保存データ（新フィールドが無い JSON）でも既存値を保ったまま読めるようにする
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        autoClean = try c.decodeIfPresent(Bool.self, forKey: .autoClean) ?? false
        thresholdPercent = try c.decodeIfPresent(Double.self, forKey: .thresholdPercent) ?? 90
        minFreeGB = try c.decodeIfPresent(Double.self, forKey: .minFreeGB) ?? 10
        criticalFreeGB = try c.decodeIfPresent(Double.self, forKey: .criticalFreeGB) ?? 5
        emergencyFreeGB = try c.decodeIfPresent(Double.self, forKey: .emergencyFreeGB) ?? 2
    }
}

// MARK: - DiskGuard

/// ディスク使用状況を定期監視し、圧迫時に「リスクのないキャッシュ/ログ」の
/// 安全な削除を提案（または承認済みなら自動実行）するサービス。
@MainActor
final class DiskGuard: ObservableObject {
    static let shared = DiskGuard()

    /// UI に提示中の提案（手動モードで圧迫検知した時にセット）
    @Published private(set) var pendingPlan: SafeCleanupPlan?
    /// 現在の圧迫レベル（UI がバッジ/色を出し分けるため）
    @Published private(set) var pressureLevel: DiskPressureLevel = .normal
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
    /// 緊急時の再試行間隔（1 時間）。緊急でも毎分スキャン/削除して重くならないようにする。
    private let emergencyCooldown: TimeInterval = 60 * 60

    private init() {
        if let data = defaults.data(forKey: settingsKey),
           let saved = try? JSONDecoder().decode(DiskGuardSettings.self, from: data) {
            self.settings = saved
        } else {
            self.settings = DiskGuardSettings()
        }
    }

    // MARK: - 監視

    /// 空き容量から現在の圧迫レベルを判定する。
    func level(for info: StorageInfo) -> DiskPressureLevel {
        if info.freeGB < settings.emergencyFreeGB { return .emergency }
        if info.freeGB < settings.criticalFreeGB { return .critical }
        if info.freeGB < settings.minFreeGB || info.usagePercent >= settings.thresholdPercent { return .notice }
        return .normal
    }

    /// AppDelegate の定期タイマーから呼ぶ。圧迫レベルに応じて段階的に介入する。
    func evaluate() {
        guard settings.enabled else { return }

        let info = analyzer.getStorageInfo()
        guard info.totalGB > 0 else { return }

        let level = self.level(for: info)
        pressureLevel = level
        guard level != .normal else { return }

        // 【緊急】0バイト到達（OS/他アプリ/自アプリが不安定になる）を避けるため、クールダウンを無視して
        // 必ず気付けるようにする。ただし削除は勝手にやらず、通知＋承認（ワンボタン）を取る。
        // ユーザーが自動削除モード(autoClean)を明示的に ON にしている場合のみ、その同意に基づき自動実行する。
        if level == .emergency {
            // 緊急でも毎分スキャン/削除はしない。前回対応から一定時間(30分)空いた時だけ動く。
            // ＝1回空けたら、まだ空きが少なくても30分は再スキャンしない（無駄なI/Oと体感悪化を防ぐ）。
            guard emergencyCooldownElapsed else { return }
            markActionTaken() // 先にクールダウンを立て、非同期削除中やスキャン中の再トリガーを防ぐ

            let candidates = buildCandidates()
            guard !candidates.isEmpty else {
                // 安全に消せる物が無い緊急時 → 大物の助言つきで強く通知（削除はしない）
                notify(title: "⚠️ 空き容量が極めて少なくなっています", body: emergencyBody(info))
                return
            }
            let plan = SafeCleanupPlan(candidates: candidates,
                                      usagePercentBefore: info.usagePercent, freeGBBefore: info.freeGB)
            if settings.autoClean {
                // 自動削除に同意済み → 実行
                performCleanup(plan, auto: true, emergency: true)
            } else {
                // 承認フロー：一覧＋ワンボタンを UI に出し、緊急として強く通知
                pendingPlan = plan
                notify(title: "⚠️ 緊急：空き容量が極めて少ない",
                       body: "\(emergencyBody(info))\nアプリを開けば、安全な項目をワンボタンで解放できます（削除は承認後のみ）。")
            }
            return
        }

        // すでに提案を出しているなら重複させない
        guard pendingPlan == nil else { return }
        // クールダウン中はスキップ
        guard cooldownElapsed else { return }

        // 安全候補（キャッシュ/ログのみ・フォント等の保護対象は除外）を収集
        let candidates = buildCandidates()
        guard !candidates.isEmpty else {
            // 消せる安全物が無くても、危険域なら大物の内訳だけは知らせる
            if level >= .critical {
                notify(title: title(for: level), body: emergencyBody(info))
                markActionTaken()
            }
            return
        }

        let plan = SafeCleanupPlan(
            candidates: candidates,
            usagePercentBefore: info.usagePercent,
            freeGBBefore: info.freeGB
        )

        if settings.autoClean {
            // 承認済み → 自動で空けて通知のみ
            performCleanup(plan, auto: true, emergency: false)
        } else {
            // 手動 → 提案を UI に出し、気付けるよう通知（危険域ほど強い文言）
            pendingPlan = plan
            let extra = level >= .critical ? "空き残り約\(String(format: "%.1f", info.freeGB))GB。" : ""
            notify(
                title: title(for: level),
                body: "\(extra)安全に空けられる項目が最大 約\(plan.totalFormatted)あります。アプリを開けばワンボタンで解放できます（実際の解放量は削除後にお知らせ）。"
            )
        }
    }

    private func title(for level: DiskPressureLevel) -> String {
        switch level {
        case .emergency: return "⚠️ 緊急：空き容量が極めて少ない"
        case .critical:  return "⚠️ 空き容量が少なくなっています"
        case .notice:    return "ストレージ圧迫を検知しました"
        case .normal:    return "ストレージ"
        }
    }

    /// 緊急/危険時の本文。安全に消せる物が乏しい時に「次に効く大物」を助言する。
    private func emergencyBody(_ info: StorageInfo) -> String {
        var lines = ["空き残り約\(String(format: "%.1f", info.freeGB))GB（使用\(String(format: "%.0f", info.usagePercent))%）。"]
        let big = bigConsumerHints()
        if !big.isEmpty {
            lines.append("容量の大きい項目: " + big.prefix(3).joined(separator: " / "))
        }
        lines.append("アプリを開くと、安全な項目はワンボタンで、大きい項目は個別確認の上で整理できます。")
        return lines.joined(separator: "\n")
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

    private func performCleanup(_ plan: SafeCleanupPlan, auto: Bool, emergency: Bool = false) {
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
            await self.finishCleanup(cleared: cleared, freedMB: freedMB, auto: auto, emergency: emergency)
        }
    }

    private func finishCleanup(cleared: Int, freedMB: Double, auto: Bool, emergency: Bool) {
        markActionTaken()
        pendingPlan = nil

        // 実際にはほぼ空かなかった（対象が使用中／既に空 等）→ 誤解を招く「確保しました」は出さない。
        // 通常時は無通知、緊急時のみ「空けられなかった＋大物の助言」を正直に知らせる。
        if freedMB < 1 {
            lastAutoCleanSummary = "安全に空けられる余地はほとんどありませんでした。"
            if emergency {
                var body = "自動で空けられる安全なキャッシュ/ログはほぼありませんでした。"
                let big = bigConsumerHints()
                if !big.isEmpty {
                    body += "\n容量の大きい項目: " + big.prefix(2).joined(separator: " / ") + "（アプリから個別に確認して整理できます）"
                }
                notify(title: "空き容量にご注意ください", body: body)
            }
            return
        }

        let freedText = freedMB >= 1024 ? String(format: "%.1f GB", freedMB / 1024) : String(format: "%.0f MB", freedMB)
        var summary = "\(cleared)項目のキャッシュ/ログを削除し、約\(freedText)を確保しました。"

        // 緊急自動解放でもまだ危険域なら、次の一手（大物）を助言する
        if emergency {
            let info = analyzer.getStorageInfo()
            if info.freeGB < settings.criticalFreeGB {
                let big = bigConsumerHints()
                if !big.isEmpty { summary += "\nまだ空きが少なめです。大きい項目: " + big.prefix(2).joined(separator: " / ") }
            }
        }
        lastAutoCleanSummary = summary

        notify(
            title: emergency ? "緊急：安全な項目を自動で解放しました"
                 : (auto ? "ストレージを自動で空けました" : "ストレージを空けました"),
            body: summary
        )
    }

    // MARK: - AI(ローカル/無料)による「次に効く大物」の助言

    /// 容量の大きい"要判断"項目を素早く見つけ、人が読める助言にする（ローカル完結・無料）。
    /// 通知に載せる用途のため軽量に。詳しい一覧は optimalAdvice() / フルスキャンで。
    private func bigConsumerHints() -> [String] {
        let home = NSHomeDirectory()
        let fm = FileManager.default
        let candidates: [(String, String)] = [
            ("\(home)/.ollama/models", "Ollamaモデル"),
            ("\(home)/Library/Developer/CoreSimulator/Devices", "iOSシミュレータ"),
            ("\(home)/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw", "Dockerイメージ"),
            // iCloud関連の隠れた大物（削除ではなく退避/自動purgeで空ける。安全キャッシュには含めない）
            ("\(home)/Library/Caches/CloudKit", "CloudKitキャッシュ(iCloud管理)"),
            ("\(home)/Library/Mobile Documents/com~apple~CloudDocs", "iCloud Driveローカル(退避で空く)"),
            ("\(home)/Downloads", "ダウンロード"),
        ]
        var hints: [(String, Double)] = []
        for (path, label) in candidates {
            guard fm.fileExists(atPath: path) else { continue }
            if let mb = directorySizeQuick(path), mb >= 1024 {
                hints.append(("\(label) \(String(format: "%.1fGB", mb / 1024))", mb))
            }
        }
        var result = hints.sorted { $0.1 > $1.1 }.map { $0.0 }
        // ローカル Time Machine スナップショットは容量を食う定番。存在すれば最優先で知らせる。
        let snaps = localSnapshotCount()
        if snaps > 0 { result.insert("Time Machineローカルスナップショット \(snaps)個", at: 0) }
        return result
    }

    /// ローカル Time Machine スナップショットの数を返す（tmutil。容量圧迫の定番要因の検出）。
    private func localSnapshotCount() -> Int {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        p.arguments = ["listlocalsnapshots", "/"]
        let outPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.split(separator: "\n").filter { $0.contains("com.apple.TimeMachine") }.count
        } catch {
            return 0
        }
    }

    /// ざっくりディレクトリ/ファイルサイズ(MB)。厳密さより速度優先。
    private func directorySizeQuick(_ path: String) -> Double? {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDir) else { return nil }
        if !isDir.boolValue {
            let attrs = try? fm.attributesOfItem(atPath: path)
            return (attrs?[.size] as? NSNumber).map { $0.doubleValue / 1_000_000 }
        }
        guard let en = fm.enumerator(at: URL(fileURLWithPath: path),
                                     includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                     options: [.skipsHiddenFiles]) else { return nil }
        var total: Double = 0
        var scanned = 0
        // メインスレッドを固めないよう走査上限を設ける（CloudKit等の巨大キャッシュ対策）。
        // 上限に達しても「大物」と分かれば十分なので途中打ち切りでよい（サイズは下限扱い）。
        let maxEntries = 40_000
        for case let url as URL in en {
            if let s = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                total += Double(s)
            }
            scanned += 1
            if scanned >= maxEntries { break }
        }
        return total / 1_000_000
    }

    /// 緊急時の最終手段：アプリ経由でなく手動で確実に空けられる、安全な（再生成される）コマンド一覧。
    /// 万一アプリ操作もままならない極限状態のためのフォールバック（コピーして外部ターミナルで実行）。
    static let emergencyTerminalCommands: [String] = [
        "rm -rf ~/Library/Developer/Xcode/DerivedData/*",
        "rm -rf ~/Library/Caches/* ~/.cache/*",
        "npm cache clean --force; brew cleanup -s",
        "xcrun simctl delete unavailable",
        "sudo tmutil thinlocalsnapshots / 999999999999 4"
    ]

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

    private var emergencyCooldownElapsed: Bool {
        guard let last = defaults.object(forKey: lastActionKey) as? TimeInterval else { return true }
        return Date().timeIntervalSince1970 - last >= emergencyCooldown
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
        // ストレージ圧迫は重要。集中モード中でも気付けるよう time-sensitive にする。
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
