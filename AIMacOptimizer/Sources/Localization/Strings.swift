import Foundation

/// Supported languages
enum AppLanguage: String, CaseIterable, Codable {
    case japanese = "ja"
    case english = "en"
    case chinese = "zh"

    var displayName: String {
        switch self {
        case .japanese: return "日本語"
        case .english: return "English"
        case .chinese: return "中文"
        }
    }

    /// Detect system language, fallback to English
    static var system: AppLanguage {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("ja") { return .japanese }
        if preferred.hasPrefix("zh") { return .chinese }
        return .english
    }
}

/// Centralized localization strings
struct L10n {
    static var current: AppLanguage = .system

    // MARK: - General
    static var appName: String { "AI Mac Optimizer" }

    static var used: String {
        switch current {
        case .japanese: return "使用中"
        case .english: return "Used"
        case .chinese: return "使用中"
        }
    }

    static var free: String {
        switch current {
        case .japanese: return "空き"
        case .english: return "Free"
        case .chinese: return "可用"
        }
    }

    static var swap: String {
        switch current {
        case .japanese: return "スワップ"
        case .english: return "Swap"
        case .chinese: return "交换"
        }
    }

    // MARK: - Memory Severity
    static var severityLow: String {
        switch current {
        case .japanese: return "良好"
        case .english: return "Good"
        case .chinese: return "良好"
        }
    }

    static var severityMedium: String {
        switch current {
        case .japanese: return "注意"
        case .english: return "Warning"
        case .chinese: return "注意"
        }
    }

    static var severityHigh: String {
        switch current {
        case .japanese: return "危険"
        case .english: return "Critical"
        case .chinese: return "严重"
        }
    }

    // MARK: - Sections
    static var memoryUsage: String {
        switch current {
        case .japanese: return "メモリ状況"
        case .english: return "Memory"
        case .chinese: return "内存"
        }
    }

    static var storageUsage: String {
        switch current {
        case .japanese: return "ストレージ"
        case .english: return "Storage"
        case .chinese: return "存储"
        }
    }

    static var topProcesses: String {
        switch current {
        case .japanese: return "メモリ使用量ランキング"
        case .english: return "Top Memory Usage"
        case .chinese: return "内存使用排行"
        }
    }

    static var suggestions: String {
        switch current {
        case .japanese: return "AI最適化提案"
        case .english: return "AI Suggestions"
        case .chinese: return "AI优化建议"
        }
    }

    static var noSuggestions: String {
        switch current {
        case .japanese: return "現在、最適化の提案はありません"
        case .english: return "No optimization suggestions at this time"
        case .chinese: return "目前没有优化建议"
        }
    }

    // MARK: - Actions
    static var oneClickOptimize: String {
        switch current {
        case .japanese: return "ワンクリック最適化"
        case .english: return "One-Click Optimize"
        case .chinese: return "一键优化"
        }
    }

    static var analyzing: String {
        switch current {
        case .japanese: return "分析中..."
        case .english: return "Analyzing..."
        case .chinese: return "分析中..."
        }
    }

    static func optimizing(count: Int) -> String {
        switch current {
        case .japanese: return "最適化を実行中... (\(count)件)"
        case .english: return "Optimizing... (\(count) items)"
        case .chinese: return "优化中... (\(count)项)"
        }
    }

    static func freedMemory(mb: Double) -> String {
        let formatted = mb >= 1024
            ? String(format: "%.1f GB", mb / 1024)
            : String(format: "%.0f MB", mb)
        switch current {
        case .japanese: return "約 \(formatted) 解放しました"
        case .english: return "Freed approximately \(formatted)"
        case .chinese: return "已释放约 \(formatted)"
        }
    }

    // MARK: - Settings
    static var settings: String {
        switch current {
        case .japanese: return "設定"
        case .english: return "Settings"
        case .chinese: return "设置"
        }
    }

    static var quit: String {
        switch current {
        case .japanese: return "終了"
        case .english: return "Quit"
        case .chinese: return "退出"
        }
    }

    static var general: String {
        switch current {
        case .japanese: return "一般"
        case .english: return "General"
        case .chinese: return "通用"
        }
    }

    static var monitoring: String {
        switch current {
        case .japanese: return "監視"
        case .english: return "Monitoring"
        case .chinese: return "监控"
        }
    }

    static var notifications: String {
        switch current {
        case .japanese: return "通知"
        case .english: return "Notifications"
        case .chinese: return "通知"
        }
    }

    static var about: String {
        switch current {
        case .japanese: return "情報"
        case .english: return "About"
        case .chinese: return "关于"
        }
    }

    static var language: String {
        switch current {
        case .japanese: return "言語"
        case .english: return "Language"
        case .chinese: return "语言"
        }
    }

    // MARK: - Storage Actions (Confirmation Required)
    static func confirmDelete(name: String, size: String) -> String {
        switch current {
        case .japanese: return "「\(name)」(\(size))を削除しますか？この操作は元に戻せません。"
        case .english: return "Delete \"\(name)\" (\(size))? This action cannot be undone."
        case .chinese: return "删除「\(name)」(\(size))？此操作无法撤销。"
        }
    }

    static func confirmMoveToTrash(name: String, size: String) -> String {
        switch current {
        case .japanese: return "「\(name)」(\(size))をゴミ箱に移動しますか？"
        case .english: return "Move \"\(name)\" (\(size)) to Trash?"
        case .chinese: return "将「\(name)」(\(size))移至废纸篓？"
        }
    }

    static func confirmMoveToICloud(name: String, size: String) -> String {
        switch current {
        case .japanese: return "「\(name)」(\(size))をiCloud Driveに退避しますか？"
        case .english: return "Move \"\(name)\" (\(size)) to iCloud Drive?"
        case .chinese: return "将「\(name)」(\(size))移至iCloud Drive？"
        }
    }

    // MARK: - Schedule
    static var autoOptimization: String {
        switch current {
        case .japanese: return "自動最適化"
        case .english: return "Auto Optimization"
        case .chinese: return "自动优化"
        }
    }

    static var scheduleEnabled: String {
        switch current {
        case .japanese: return "スケジュール最適化を有効にする"
        case .english: return "Enable scheduled optimization"
        case .chinese: return "启用定时优化"
        }
    }

    // MARK: - Deep Diagnosis

    static var diagnosis: String {
        switch current {
        case .japanese: return "診断"
        case .english: return "Diagnosis"
        case .chinese: return "诊断"
        }
    }

    static var deepDiagnosis: String {
        switch current {
        case .japanese: return "Deep Diagnosis"
        case .english: return "Deep Diagnosis"
        case .chinese: return "深度诊断"
        }
    }

    static var startDiagnosis: String {
        switch current {
        case .japanese: return "診断を開始"
        case .english: return "Start Diagnosis"
        case .chinese: return "开始诊断"
        }
    }

    static var diagnosisResult: String {
        switch current {
        case .japanese: return "診断結果"
        case .english: return "Diagnosis Result"
        case .chinese: return "诊断结果"
        }
    }

    static var askAI: String {
        switch current {
        case .japanese: return "AIに相談する"
        case .english: return "Ask AI"
        case .chinese: return "咨询AI"
        }
    }

    static var aiChat: String {
        switch current {
        case .japanese: return "AI相談"
        case .english: return "AI Chat"
        case .chinese: return "AI咨询"
        }
    }

    static var reDiagnose: String {
        switch current {
        case .japanese: return "再診断"
        case .english: return "Re-diagnose"
        case .chinese: return "重新诊断"
        }
    }

    // MARK: - Tabs & Common Labels
    static var tools: String {
        switch current {
        case .japanese: return "ツール"
        case .english: return "Tools"
        case .chinese: return "工具"
        }
    }

    static var upgradeToPro: String {
        switch current {
        case .japanese: return "Pro にアップグレード"
        case .english: return "Upgrade to Pro"
        case .chinese: return "升级到 Pro"
        }
    }

    static var toPro: String {
        switch current {
        case .japanese: return "Pro へ"
        case .english: return "Go Pro"
        case .chinese: return "升级 Pro"
        }
    }

    static var upgrade: String {
        switch current {
        case .japanese: return "アップグレード"
        case .english: return "Upgrade"
        case .chinese: return "升级"
        }
    }

    static var cancel: String {
        switch current {
        case .japanese: return "キャンセル"
        case .english: return "Cancel"
        case .chinese: return "取消"
        }
    }

    static var confirm: String {
        switch current {
        case .japanese: return "確認"
        case .english: return "Confirm"
        case .chinese: return "确认"
        }
    }

    static var later: String {
        switch current {
        case .japanese: return "後で"
        case .english: return "Later"
        case .chinese: return "稍后"
        }
    }

    static var stop: String {
        switch current {
        case .japanese: return "停止"
        case .english: return "Stop"
        case .chinese: return "停止"
        }
    }

    static var skip: String {
        switch current {
        case .japanese: return "スキップ"
        case .english: return "Skip"
        case .chinese: return "跳过"
        }
    }

    static var recommended: String {
        switch current {
        case .japanese: return "推奨"
        case .english: return "Recommended"
        case .chinese: return "推荐"
        }
    }

    static var recommendedBadge: String {
        switch current {
        case .japanese: return "おすすめ"
        case .english: return "Best Value"
        case .chinese: return "推荐"
        }
    }

    static var startScan: String {
        switch current {
        case .japanese: return "スキャン開始"
        case .english: return "Start Scan"
        case .chinese: return "开始扫描"
        }
    }

    static var proFeature: String {
        switch current {
        case .japanese: return "Pro機能"
        case .english: return "Pro Feature"
        case .chinese: return "Pro 功能"
        }
    }

    // MARK: - Memory Tab
    static var showMore: String {
        switch current {
        case .japanese: return "閉じる"
        case .english: return "Show less"
        case .chinese: return "收起"
        }
    }

    static func showTopProcesses(count: Int) -> String {
        switch current {
        case .japanese: return "もっと見る（上位\(count)件）"
        case .english: return "Show more (top \(count))"
        case .chinese: return "查看更多（前\(count)项）"
        }
    }

    static var recommendations: String {
        switch current {
        case .japanese: return "おすすめ"
        case .english: return "Recommended"
        case .chinese: return "推荐"
        }
    }

    static func maxSavingEstimate(_ formatted: String) -> String {
        switch current {
        case .japanese: return "最大 約\(formatted)（目安）"
        case .english: return "Up to ~\(formatted) (estimate)"
        case .chinese: return "最多约\(formatted)（估计）"
        }
    }

    static var optimizeDone: String {
        switch current {
        case .japanese: return "最適化を実行しました"
        case .english: return "Optimization complete"
        case .chinese: return "优化已完成"
        }
    }

    static func optimizeResult(_ parts: String) -> String {
        switch current {
        case .japanese: return parts + " を解放しました"
        case .english: return "Freed " + parts
        case .chinese: return "已释放 " + parts
        }
    }

    static func memoryAmount(_ formatted: String) -> String {
        switch current {
        case .japanese: return "メモリ約 \(formatted)"
        case .english: return "~\(formatted) memory"
        case .chinese: return "内存约 \(formatted)"
        }
    }

    static func diskAmount(_ formatted: String) -> String {
        switch current {
        case .japanese: return "ストレージ約 \(formatted)"
        case .english: return "~\(formatted) storage"
        case .chinese: return "存储约 \(formatted)"
        }
    }

    // MARK: - Storage Tab
    static var storageAutoCleanEnabled: String {
        switch current {
        case .japanese: return "ストレージ自動削除: 有効"
        case .english: return "Auto storage cleanup: On"
        case .chinese: return "存储自动清理: 已启用"
        }
    }

    static var storageAutoCleanDesc: String {
        switch current {
        case .japanese: return "圧迫時に安全なキャッシュ/ログを自動削除し通知します"
        case .english: return "Automatically deletes safe caches/logs when space is low and notifies you"
        case .chinese: return "空间不足时自动删除安全的缓存/日志并通知您"
        }
    }

    static func confirmStorageAction(parent: String, count: Int, size: String, action: String) -> String {
        switch current {
        case .japanese: return "\(parent) から \(count)件 (\(size)) を\(action)しますか？"
        case .english: return "\(action) \(count) item(s) (\(size)) from \(parent)?"
        case .chinese: return "从 \(parent) \(action) \(count) 项 (\(size))？"
        }
    }

    static var storagePressureDetected: String {
        switch current {
        case .japanese: return "ストレージ圧迫を検知"
        case .english: return "Low storage detected"
        case .chinese: return "检测到存储空间不足"
        }
    }

    static func storageUsageSummary(percent: Int, freeGB: String) -> String {
        switch current {
        case .japanese: return "使用 \(percent)% / 空き \(freeGB)GB"
        case .english: return "Used \(percent)% / Free \(freeGB)GB"
        case .chinese: return "已用 \(percent)% / 可用 \(freeGB)GB"
        }
    }

    static func safeCleanupAvailable(_ total: String) -> String {
        switch current {
        case .japanese: return "リスクのないキャッシュ/ログを最大 約\(total) 安全に削除できます（実際の解放量は削除後に表示）。"
        case .english: return "Up to about \(total) of risk-free caches/logs can be safely deleted (actual amount shown after deletion)."
        case .chinese: return "最多可安全删除约 \(total) 无风险的缓存/日志（实际释放量在删除后显示）。"
        }
    }

    static var autoCleanFromNow: String {
        switch current {
        case .japanese: return "今後、圧迫を検知したら自動で空ける（通知のみ）"
        case .english: return "Automatically free space when low from now on (notify only)"
        case .chinese: return "今后检测到空间不足时自动清理（仅通知）"
        }
    }

    static func cleanNowSafely(_ total: String) -> String {
        switch current {
        case .japanese: return "今すぐ安全に空ける（\(total)）"
        case .english: return "Free up safely now (\(total))"
        case .chinese: return "立即安全清理（\(total)）"
        }
    }

    static var cleanupStarted: String {
        switch current {
        case .japanese: return "ストレージの掃除を実行しました（結果は通知でお知らせします）"
        case .english: return "Storage cleanup started (results will be shown in a notification)"
        case .chinese: return "已开始清理存储（结果将通过通知告知）"
        }
    }

    static var proRequiredForDeletion: String {
        switch current {
        case .japanese: return "削除にはProが必要です"
        case .english: return "Deletion requires Pro"
        case .chinese: return "删除需要 Pro"
        }
    }

    static var scanResultsFreeOK: String {
        switch current {
        case .japanese: return "スキャン結果の確認はFreeでもOK"
        case .english: return "Viewing scan results is free"
        case .chinese: return "查看扫描结果免费即可"
        }
    }

    static var noFiles: String {
        switch current {
        case .japanese: return "ファイルがありません"
        case .english: return "No files"
        case .chinese: return "没有文件"
        }
    }

    static var clearChecked: String {
        switch current {
        case .japanese: return "チェック済みをクリア"
        case .english: return "Clear checked"
        case .chinese: return "清除已选"
        }
    }

    static var moveCheckedToTrash: String {
        switch current {
        case .japanese: return "チェック済みをゴミ箱に移動"
        case .english: return "Move checked to Trash"
        case .chinese: return "将已选移至废纸篓"
        }
    }

    static var moveCheckedToICloud: String {
        switch current {
        case .japanese: return "チェック済みをiCloudに退避"
        case .english: return "Move checked to iCloud"
        case .chinese: return "将已选移至 iCloud"
        }
    }

    static var clear: String {
        switch current {
        case .japanese: return "クリア"
        case .english: return "Clear"
        case .chinese: return "清除"
        }
    }

    static var toTrash: String {
        switch current {
        case .japanese: return "ゴミ箱へ"
        case .english: return "To Trash"
        case .chinese: return "移至废纸篓"
        }
    }

    static var iCloud: String { "iCloud" }

    static func selectedCount(_ count: Int) -> String {
        switch current {
        case .japanese: return "\(count)件 選択中"
        case .english: return "\(count) selected"
        case .chinese: return "已选 \(count) 项"
        }
    }

    static func clearedCount(_ count: Int) -> String {
        switch current {
        case .japanese: return "✅ \(count)件をクリアしました"
        case .english: return "✅ Cleared \(count) item(s)"
        case .chinese: return "✅ 已清除 \(count) 项"
        }
    }

    static func actionDoneCount(_ count: Int, action: String) -> String {
        switch current {
        case .japanese: return "✅ \(count)件を\(action)しました"
        case .english: return "✅ \(action): \(count) item(s)"
        case .chinese: return "✅ 已\(action) \(count) 项"
        }
    }

    static func actionFailedCount(_ count: Int) -> String {
        switch current {
        case .japanese: return " (❌ \(count)件失敗)"
        case .english: return " (❌ \(count) failed)"
        case .chinese: return " (❌ \(count) 项失败)"
        }
    }

    static var operationFailed: String {
        switch current {
        case .japanese: return "❌ 操作に失敗しました"
        case .english: return "❌ Operation failed"
        case .chinese: return "❌ 操作失败"
        }
    }

    // MARK: - Tools / Battery
    static var battery: String {
        switch current {
        case .japanese: return "バッテリー"
        case .english: return "Battery"
        case .chinese: return "电池"
        }
    }

    static var appManagement: String {
        switch current {
        case .japanese: return "アプリ管理"
        case .english: return "Apps"
        case .chinese: return "应用管理"
        }
    }

    static var batteryHealth: String {
        switch current {
        case .japanese: return "バッテリーヘルス"
        case .english: return "Battery Health"
        case .chinese: return "电池健康"
        }
    }

    static var healthLevel: String {
        switch current {
        case .japanese: return "健康度"
        case .english: return "Health"
        case .chinese: return "健康度"
        }
    }

    static var chargingStatus: String {
        switch current {
        case .japanese: return "充電状態"
        case .english: return "Charging"
        case .chinese: return "充电状态"
        }
    }

    static var charging: String {
        switch current {
        case .japanese: return "充電中"
        case .english: return "Charging"
        case .chinese: return "充电中"
        }
    }

    static var onBattery: String {
        switch current {
        case .japanese: return "バッテリー使用中"
        case .english: return "On battery"
        case .chinese: return "使用电池中"
        }
    }

    static var batteryLevel: String {
        switch current {
        case .japanese: return "バッテリー残量"
        case .english: return "Battery level"
        case .chinese: return "电池电量"
        }
    }

    static var chargeCycles: String {
        switch current {
        case .japanese: return "充電サイクル"
        case .english: return "Charge cycles"
        case .chinese: return "充电循环"
        }
    }

    static func cycleCountValue(_ count: Int) -> String {
        switch current {
        case .japanese: return "\(count)回"
        case .english: return "\(count)"
        case .chinese: return "\(count)次"
        }
    }

    static var maxCapacity: String {
        switch current {
        case .japanese: return "最大容量"
        case .english: return "Max capacity"
        case .chinese: return "最大容量"
        }
    }

    static var designCapacity: String {
        switch current {
        case .japanese: return "設計容量"
        case .english: return "Design capacity"
        case .chinese: return "设计容量"
        }
    }

    static var temperature: String {
        switch current {
        case .japanese: return "温度"
        case .english: return "Temperature"
        case .chinese: return "温度"
        }
    }

    static var timeRemainingLabel: String {
        switch current {
        case .japanese: return "残り時間"
        case .english: return "Time remaining"
        case .chinese: return "剩余时间"
        }
    }

    static var batteryTips: String {
        switch current {
        case .japanese: return "バッテリーのコツ"
        case .english: return "Battery Tips"
        case .chinese: return "电池小贴士"
        }
    }

    static var batteryTipReplace: String {
        switch current {
        case .japanese: return "充電サイクルが800回を超えています。バッテリー交換を検討してください。"
        case .english: return "Charge cycles have exceeded 800. Consider replacing the battery."
        case .chinese: return "充电循环已超过 800 次。建议考虑更换电池。"
        }
    }

    static var batteryTipRange: String {
        switch current {
        case .japanese: return "20%～80%の範囲で使うとバッテリー寿命が延びます。"
        case .english: return "Keeping charge between 20% and 80% extends battery lifespan."
        case .chinese: return "将电量保持在 20%～80% 之间可延长电池寿命。"
        }
    }

    static var noBattery: String {
        switch current {
        case .japanese: return "バッテリー非搭載"
        case .english: return "No Battery"
        case .chinese: return "无电池"
        }
    }

    static var noBatteryDesc: String {
        switch current {
        case .japanese: return "このMacにはバッテリーが搭載されていません"
        case .english: return "This Mac does not have a battery"
        case .chinese: return "此 Mac 未配备电池"
        }
    }

    // MARK: - Tools / App Uninstaller
    static var scanningApps: String {
        switch current {
        case .japanese: return "アプリをスキャン中..."
        case .english: return "Scanning apps..."
        case .chinese: return "正在扫描应用..."
        }
    }

    static var detectLeftovers: String {
        switch current {
        case .japanese: return "インストール済みアプリと残留ファイルを検出"
        case .english: return "Detect installed apps and leftover files"
        case .chinese: return "检测已安装应用和残留文件"
        }
    }

    static func appsCount(_ count: Int) -> String {
        switch current {
        case .japanese: return "\(count)個のアプリ"
        case .english: return "\(count) apps"
        case .chinese: return "\(count) 个应用"
        }
    }

    static func leftoverTotal(_ size: String) -> String {
        switch current {
        case .japanese: return "残留ファイル: \(size)"
        case .english: return "Leftovers: \(size)"
        case .chinese: return "残留文件: \(size)"
        }
    }

    static var leftoverExplanation: String {
        switch current {
        case .japanese: return "「残留ファイル」＝このアプリが残した設定・キャッシュ・ログなどの補助データです。アプリを消しても残りがちで、少しずつ容量を圧迫します。"
        case .english: return "\"Leftover files\" are the settings, caches, and logs an app leaves behind. They often remain after the app is removed and gradually consume disk space."
        case .chinese: return "「残留文件」是应用留下的设置、缓存和日志等辅助数据。删除应用后它们通常仍会残留，逐渐占用磁盘空间。"
        }
    }

    static func leftoverHeader(count: Int, size: String) -> String {
        switch current {
        case .japanese: return "残留ファイル（\(count)件 / \(size)） — 項目ごとに種類・リスクが違います。残すものはチェックを外してください"
        case .english: return "Leftover files (\(count) items / \(size)) — type and risk vary per item. Uncheck anything you want to keep."
        case .chinese: return "残留文件（\(count) 项 / \(size)）— 每项的类型和风险不同。请取消勾选想要保留的项目。"
        }
    }

    static func leftoverRiskLabel(_ risk: String) -> String {
        switch current {
        case .japanese: return "リスク\(risk)"
        case .english: return "Risk: \(risk)"
        case .chinese: return "风险\(risk)"
        }
    }

    static var leftoverRemoveTitle: String {
        switch current {
        case .japanese: return "残留削除"
        case .english: return "Remove Leftovers"
        case .chinese: return "删除残留"
        }
    }

    static var uninstallTitle: String {
        switch current {
        case .japanese: return "アンインストール"
        case .english: return "Uninstall"
        case .chinese: return "卸载"
        }
    }

    static var riskLow: String {
        switch current {
        case .japanese: return "リスク低"
        case .english: return "Low risk"
        case .chinese: return "低风险"
        }
    }

    static var riskMedium: String {
        switch current {
        case .japanese: return "リスク中"
        case .english: return "Medium risk"
        case .chinese: return "中风险"
        }
    }

    static var leftoverRemoveDesc: String {
        switch current {
        case .japanese: return "アプリ本体は残し、残留ファイルだけをゴミ箱へ。アプリは引き続き使えます。"
        case .english: return "Keeps the app itself and moves only leftover files to Trash. The app remains usable."
        case .chinese: return "保留应用本体，仅将残留文件移至废纸篓。应用仍可继续使用。"
        }
    }

    static var uninstallDesc: String {
        switch current {
        case .japanese: return "アプリ本体＋残留ファイルをまとめてゴミ箱へ。このアプリは使えなくなります（再び使うには再インストールが必要）。"
        case .english: return "Moves the app and its leftover files to Trash. The app will no longer be usable (reinstall required to use again)."
        case .chinese: return "将应用本体和残留文件一并移至废纸篓。此应用将无法使用（需重新安装才能再次使用）。"
        }
    }

    static var uninstallConfirmTitle: String {
        switch current {
        case .japanese: return "アンインストールしますか？"
        case .english: return "Uninstall this app?"
        case .chinese: return "要卸载吗？"
        }
    }

    static var removeLeftoversConfirmTitle: String {
        switch current {
        case .japanese: return "残留ファイルを削除しますか？"
        case .english: return "Remove leftover files?"
        case .chinese: return "要删除残留文件吗？"
        }
    }

    static func uninstallConfirmDesc(app: String) -> String {
        switch current {
        case .japanese: return "「\(app)」の本体と残留ファイルをゴミ箱へ移動します。アプリは使えなくなります（再び使うには再インストールが必要）。"
        case .english: return "Moves \"\(app)\" and its leftover files to Trash. The app will no longer be usable (reinstall required)."
        case .chinese: return "将「\(app)」的本体和残留文件移至废纸篓。应用将无法使用（需重新安装）。"
        }
    }

    static func removeLeftoversConfirmDesc(count: Int) -> String {
        switch current {
        case .japanese: return "選択した残留 \(count)件 をゴミ箱へ移動します。アプリ本体は残り、引き続き使えます。チェックを外した項目は削除しません。"
        case .english: return "Moves \(count) selected leftover item(s) to Trash. The app itself remains usable. Unchecked items are not deleted."
        case .chinese: return "将所选的 \(count) 项残留文件移至废纸篓。应用本体保留并可继续使用。未勾选的项目不会被删除。"
        }
    }

    static var trashRecoverable: String {
        switch current {
        case .japanese: return "いずれもゴミ箱へ移動するだけなので、ゴミ箱を空にするまでは元に戻せます。"
        case .english: return "Everything is only moved to Trash, so you can restore it until the Trash is emptied."
        case .chinese: return "所有内容仅移至废纸篓，在清空废纸篓前均可恢复。"
        }
    }

    static var uninstallAction: String {
        switch current {
        case .japanese: return "アンインストールする"
        case .english: return "Uninstall"
        case .chinese: return "卸载"
        }
    }

    static var removeLeftoversAction: String {
        switch current {
        case .japanese: return "残留を削除する"
        case .english: return "Remove Leftovers"
        case .chinese: return "删除残留"
        }
    }

    static func leftoverLabel(_ size: String) -> String {
        switch current {
        case .japanese: return "残留: " + size
        case .english: return "Leftover: " + size
        case .chinese: return "残留: " + size
        }
    }

    static func totalLabel(_ size: String) -> String {
        switch current {
        case .japanese: return "合計: " + size
        case .english: return "Total: " + size
        case .chinese: return "合计: " + size
        }
    }

    static func leftoversMovedResult(count: Int, freed: String) -> String {
        switch current {
        case .japanese: return "残留ファイル \(count)件をゴミ箱へ移動（約\(freed)）"
        case .english: return "Moved \(count) leftover item(s) to Trash (~\(freed))"
        case .chinese: return "已将 \(count) 项残留文件移至废纸篓（约\(freed)）"
        }
    }

    static func partialFailure(_ count: Int) -> String {
        switch current {
        case .japanese: return "／一部失敗 \(count)件"
        case .english: return " / \(count) failed"
        case .chinese: return "／部分失败 \(count) 项"
        }
    }

    static func appUninstalledResult(app: String, count: Int, freed: String) -> String {
        switch current {
        case .japanese: return "「\(app)」をゴミ箱へ移動しました（\(count)項目・約\(freed)）"
        case .english: return "Moved \"\(app)\" to Trash (\(count) items, ~\(freed))"
        case .chinese: return "已将「\(app)」移至废纸篓（\(count) 项・约\(freed)）"
        }
    }

    static func uninstallPartialFailure(success: Int, errors: Int) -> String {
        switch current {
        case .japanese: return "一部失敗しました（成功 \(success)項目／エラー \(errors)件）"
        case .english: return "Partially failed (\(success) succeeded / \(errors) errors)"
        case .chinese: return "部分失败（成功 \(success) 项／错误 \(errors) 项）"
        }
    }

    // MARK: - Diagnosis View
    static var deepDiagnosisDesc: String {
        switch current {
        case .japanese: return "CPU・メモリ・ストレージ・iCloud同期など\n9項目を包括的に診断します"
        case .english: return "Comprehensively diagnoses 9 areas including CPU,\nmemory, storage, and iCloud sync"
        case .chinese: return "全面诊断 CPU、内存、存储、iCloud 同步\n等 9 个项目"
        }
    }

    static func fixAll(count: Int) -> String {
        switch current {
        case .japanese: return "全て修復 (\(count)件)"
        case .english: return "Fix All (\(count))"
        case .chinese: return "全部修复 (\(count)项)"
        }
    }

    static var fixing: String {
        switch current {
        case .japanese: return "修復中..."
        case .english: return "Fixing..."
        case .chinese: return "修复中..."
        }
    }

    static var fixAllDesc: String {
        switch current {
        case .japanese: return "自動修復可能な項目をまとめて実行し、再診断します"
        case .english: return "Runs all auto-fixable items together, then re-diagnoses"
        case .chinese: return "一并执行可自动修复的项目，然后重新诊断"
        }
    }

    static var fixComplete: String {
        switch current {
        case .japanese: return "修復完了"
        case .english: return "Fix Complete"
        case .chinese: return "修复完成"
        }
    }

    static var approvalRequired: String {
        switch current {
        case .japanese: return "個別の承認が必要な操作"
        case .english: return "Actions requiring individual approval"
        case .chinese: return "需要单独批准的操作"
        }
    }

    static var approvalRequiredDesc: String {
        switch current {
        case .japanese: return "以下はリスクがあるため自動実行していません。内容を確認して、実行するものだけ承認してください。"
        case .english: return "The following were not run automatically because they carry risk. Review them and approve only the ones you want to run."
        case .chinese: return "以下操作有风险，未自动执行。请查看内容，仅批准您想执行的项目。"
        }
    }

    static func quitRiskLabel(risk: String, detail: String) -> String {
        switch current {
        case .japanese: return "終了リスク \(risk)：\(detail)"
        case .english: return "Quit risk \(risk): \(detail)"
        case .chinese: return "退出风险 \(risk)：\(detail)"
        }
    }

    static var approveAndRun: String {
        switch current {
        case .japanese: return "承認して実行"
        case .english: return "Approve & Run"
        case .chinese: return "批准并执行"
        }
    }

    static var proMoreValue: String {
        switch current {
        case .japanese: return "Proでもっと活用"
        case .english: return "Do more with Pro"
        case .chinese: return "使用 Pro 获得更多"
        }
    }

    static var proMoreValueDesc: String {
        switch current {
        case .japanese: return "AIチャット・無制限診断・自動最適化"
        case .english: return "AI chat, unlimited diagnosis, auto optimization"
        case .chinese: return "AI 聊天・无限诊断・自动优化"
        }
    }

    static var closeDetail: String {
        switch current {
        case .japanese: return "詳細を閉じる"
        case .english: return "Hide details"
        case .chinese: return "收起详情"
        }
    }

    static var showDetail: String {
        switch current {
        case .japanese: return "詳細を確認"
        case .english: return "View details"
        case .chinese: return "查看详情"
        }
    }

    static func quitRiskInline(_ risk: String) -> String {
        switch current {
        case .japanese: return "終了リスク: \(risk)"
        case .english: return "Quit risk: \(risk)"
        case .chinese: return "退出风险: \(risk)"
        }
    }

    // MARK: - Health Trend
    static var healthTrend: String {
        switch current {
        case .japanese: return "健康状態の推移"
        case .english: return "Health Trend"
        case .chinese: return "健康状态趋势"
        }
    }

    static var last24h: String {
        switch current {
        case .japanese: return "24時間"
        case .english: return "24h"
        case .chinese: return "24小时"
        }
    }

    static var last7d: String {
        switch current {
        case .japanese: return "7日"
        case .english: return "7d"
        case .chinese: return "7天"
        }
    }

    static var last30d: String {
        switch current {
        case .japanese: return "30日"
        case .english: return "30d"
        case .chinese: return "30天"
        }
    }

    static var healthTrendProLock: String {
        switch current {
        case .japanese: return "長期の推移は Pro で解放されます（Free は直近24時間）。"
        case .english: return "Long-term trends are a Pro feature (Free shows the last 24 hours)."
        case .chinese: return "长期趋势为 Pro 功能（免费版显示最近 24 小时）。"
        }
    }

    static var collectingData: String {
        switch current {
        case .japanese: return "データ収集中です。バックグラウンドで10分ごとに記録し、しばらくすると推移が表示されます。"
        case .english: return "Collecting data. Snapshots are recorded every 10 minutes in the background; the trend will appear shortly."
        case .chinese: return "正在收集数据。后台每 10 分钟记录一次，稍后将显示趋势。"
        }
    }

    static var memoryUsagePercent: String {
        switch current {
        case .japanese: return "メモリ使用率"
        case .english: return "Memory usage"
        case .chinese: return "内存使用率"
        }
    }

    static var diskFree: String {
        switch current {
        case .japanese: return "ストレージ空き"
        case .english: return "Storage free"
        case .chinese: return "存储可用"
        }
    }

    static var cpuLoad: String {
        switch current {
        case .japanese: return "CPU負荷"
        case .english: return "CPU load"
        case .chinese: return "CPU 负载"
        }
    }

    static var current_: String {
        switch current {
        case .japanese: return "現在"
        case .english: return "Now"
        case .chinese: return "当前"
        }
    }

    static func trendStat(avg: String, unit: String, minV: String, maxV: String) -> String {
        switch current {
        case .japanese: return "平均\(avg)\(unit) ・ \(minV)〜\(maxV)"
        case .english: return "avg \(avg)\(unit) · \(minV)–\(maxV)"
        case .chinese: return "平均\(avg)\(unit) · \(minV)～\(maxV)"
        }
    }

    static func coverageSpanDays(_ days: String) -> String {
        switch current {
        case .japanese: return "実データ 直近\(days)日"
        case .english: return "Last \(days) days of data"
        case .chinese: return "最近 \(days) 天实测数据"
        }
    }

    static func coverageSpanHours(_ hours: String) -> String {
        switch current {
        case .japanese: return "実データ 直近\(hours)時間"
        case .english: return "Last \(hours) hours of data"
        case .chinese: return "最近 \(hours) 小时实测数据"
        }
    }

    static func coverageSpanMinutes(_ minutes: String) -> String {
        switch current {
        case .japanese: return "実データ 直近\(minutes)分"
        case .english: return "Last \(minutes) minutes of data"
        case .chinese: return "最近 \(minutes) 分钟实测数据"
        }
    }

    static func coverageIncomplete(span: String, count: Int, reqLabel: String) -> String {
        switch current {
        case .japanese: return "\(span) / \(count)件（まだ\(reqLabel)分そろっていません。記録が増えると差が出ます）"
        case .english: return "\(span) / \(count) points (\(reqLabel) of data not yet collected; differences appear as more is recorded)"
        case .chinese: return "\(span) / \(count) 条（尚未凑齐\(reqLabel)的数据。记录增加后会显现差异）"
        }
    }

    static func coverageComplete(span: String, count: Int) -> String {
        switch current {
        case .japanese: return "\(span) / \(count)件を表示"
        case .english: return "Showing \(span) / \(count) points"
        case .chinese: return "显示 \(span) / \(count) 条"
        }
    }

    static func rangeLabelDays(_ days: String) -> String {
        switch current {
        case .japanese: return "\(days)日"
        case .english: return "\(days) days"
        case .chinese: return "\(days)天"
        }
    }

    static var rangeLabel24h: String {
        switch current {
        case .japanese: return "24時間"
        case .english: return "24 hours"
        case .chinese: return "24 小时"
        }
    }

    // MARK: - AI Chat
    static var thinking: String {
        switch current {
        case .japanese: return "考え中..."
        case .english: return "Thinking..."
        case .chinese: return "思考中..."
        }
    }

    static var clearConversation: String {
        switch current {
        case .japanese: return "会話をクリア"
        case .english: return "Clear conversation"
        case .chinese: return "清空对话"
        }
    }

    static var freeMode: String {
        switch current {
        case .japanese: return "無料モード"
        case .english: return "Free mode"
        case .chinese: return "免费模式"
        }
    }

    static var switchAIType: String {
        switch current {
        case .japanese: return "AIの種類を切り替え（どちらも無料・キー不要）"
        case .english: return "Switch AI type (both free, no key required)"
        case .chinese: return "切换 AI 类型（均免费・无需密钥）"
        }
    }

    static var askAnythingDiagnosis: String {
        switch current {
        case .japanese: return "診断結果について何でも聞いてください"
        case .english: return "Ask me anything about the diagnosis"
        case .chinese: return "关于诊断结果，随便问我"
        }
    }

    static var suggestedQ1: String {
        switch current {
        case .japanese: return "このMacで容量を食ってるものは？"
        case .english: return "What's using up space on this Mac?"
        case .chinese: return "这台 Mac 上什么占用了空间？"
        }
    }

    static var suggestedQ2: String {
        switch current {
        case .japanese: return "安全に消せるものを教えて"
        case .english: return "What's safe to delete?"
        case .chinese: return "告诉我哪些可以安全删除"
        }
    }

    static var suggestedQ3: String {
        switch current {
        case .japanese: return "一番深刻な問題は何？"
        case .english: return "What's the most serious issue?"
        case .chinese: return "最严重的问题是什么？"
        }
    }

    static var enterQuestion: String {
        switch current {
        case .japanese: return "質問を入力..."
        case .english: return "Type your question..."
        case .chinese: return "输入你的问题..."
        }
    }

    // MARK: - Settings
    static var license: String {
        switch current {
        case .japanese: return "プラン"
        case .english: return "Plan"
        case .chinese: return "套餐"
        }
    }

    static var launchAtLogin: String {
        switch current {
        case .japanese: return "ログイン時に起動"
        case .english: return "Launch at login"
        case .chinese: return "登录时启动"
        }
    }

    static var startupSettings: String {
        switch current {
        case .japanese: return "起動設定"
        case .english: return "Startup"
        case .chinese: return "启动设置"
        }
    }

    static var refreshInterval: String {
        switch current {
        case .japanese: return "更新間隔"
        case .english: return "Refresh interval"
        case .chinese: return "刷新间隔"
        }
    }

    static func seconds(_ n: Int) -> String {
        switch current {
        case .japanese: return "\(n)秒"
        case .english: return "\(n)s"
        case .chinese: return "\(n)秒"
        }
    }

    static var performance: String {
        switch current {
        case .japanese: return "パフォーマンス"
        case .english: return "Performance"
        case .chinese: return "性能"
        }
    }

    static var currentPlan: String {
        switch current {
        case .japanese: return "現在のプラン"
        case .english: return "Current plan"
        case .chinese: return "当前套餐"
        }
    }

    static var planInfo: String {
        switch current {
        case .japanese: return "プラン情報"
        case .english: return "Plan Info"
        case .chinese: return "套餐信息"
        }
    }

    static var featureMemoryOptimize: String {
        switch current {
        case .japanese: return "メモリ最適化・Chrome/Safariタブ分析"
        case .english: return "Memory optimization & Chrome/Safari tab analysis"
        case .chinese: return "内存优化・Chrome/Safari 标签分析"
        }
    }

    static var featureDiagnosisAI: String {
        switch current {
        case .japanese: return "診断・AI相談（ローカル/無料）"
        case .english: return "Diagnosis & AI chat (local/free)"
        case .chinese: return "诊断・AI 咨询（本地/免费）"
        }
    }

    static var featureStorageScan: String {
        switch current {
        case .japanese: return "ストレージスキャン（表示）"
        case .english: return "Storage scan (view only)"
        case .chinese: return "存储扫描（仅查看）"
        }
    }

    static var featureMultiLang: String {
        switch current {
        case .japanese: return "多言語対応"
        case .english: return "Multi-language support"
        case .chinese: return "多语言支持"
        }
    }

    static var featureStorageDelete: String {
        switch current {
        case .japanese: return "ストレージのファイル削除・クリーンアップ"
        case .english: return "Storage file deletion & cleanup"
        case .chinese: return "存储文件删除・清理"
        }
    }

    static var featureScheduleOptimize: String {
        switch current {
        case .japanese: return "スケジュール自動最適化"
        case .english: return "Scheduled auto optimization"
        case .chinese: return "定时自动优化"
        }
    }

    static var featurePrioritySupport: String {
        switch current {
        case .japanese: return "優先サポート"
        case .english: return "Priority support"
        case .chinese: return "优先支持"
        }
    }

    static var havePromoCode: String {
        switch current {
        case .japanese: return "プロモコードをお持ちの方はこちら"
        case .english: return "Have a promo code?"
        case .chinese: return "有促销码？请在此输入"
        }
    }

    static var enterPromoCode: String {
        switch current {
        case .japanese: return "プロモコードを入力"
        case .english: return "Enter promo code"
        case .chinese: return "输入促销码"
        }
    }

    static var apply: String {
        switch current {
        case .japanese: return "適用"
        case .english: return "Apply"
        case .chinese: return "应用"
        }
    }

    static var promoCode: String {
        switch current {
        case .japanese: return "プロモコード"
        case .english: return "Promo Code"
        case .chinese: return "促销码"
        }
    }

    static var proMonthly: String {
        switch current {
        case .japanese: return "Pro（月額）"
        case .english: return "Pro (Monthly)"
        case .chinese: return "Pro（月付）"
        }
    }

    static var proMonthlySubtitle: String {
        switch current {
        case .japanese: return "いつでもキャンセル可能"
        case .english: return "Cancel anytime"
        case .chinese: return "随时可取消"
        }
    }

    static var proLifetime: String {
        switch current {
        case .japanese: return "Pro Lifetime"
        case .english: return "Pro Lifetime"
        case .chinese: return "Pro 终身版"
        }
    }

    static var proLifetimeSubtitle: String {
        switch current {
        case .japanese: return "買い切り・永久ライセンス"
        case .english: return "One-time purchase, lifetime license"
        case .chinese: return "一次性购买・永久许可"
        }
    }

    static var enterLicenseKeyHint: String {
        switch current {
        case .japanese: return "購入後にメールで届くライセンスキーを下記に入力してください"
        case .english: return "Enter the license key emailed to you after purchase below"
        case .chinese: return "请在下方输入购买后邮件收到的许可证密钥"
        }
    }

    static var upgradeSection: String {
        switch current {
        case .japanese: return "アップグレード"
        case .english: return "Upgrade"
        case .chinese: return "升级"
        }
    }

    static var enterLicenseKey: String {
        switch current {
        case .japanese: return "購入後にメールで届くライセンスキーを入力"
        case .english: return "Enter the license key emailed after purchase"
        case .chinese: return "输入购买后邮件收到的许可证密钥"
        }
    }

    static var licenseKey: String {
        switch current {
        case .japanese: return "ライセンスキー"
        case .english: return "License Key"
        case .chinese: return "许可证密钥"
        }
    }

    static var weeklyAISuggestionUse: String {
        switch current {
        case .japanese: return "今週のAI提案使用回数"
        case .english: return "AI suggestions used this week"
        case .chinese: return "本周 AI 建议使用次数"
        }
    }

    static var resetLicense: String {
        switch current {
        case .japanese: return "このMacのライセンスを解除"
        case .english: return "Deactivate license on this Mac"
        case .chinese: return "在此 Mac 上解除许可证"
        }
    }

    /// リセットが「課金の解約ではない」ことの補足
    static var resetLicenseNote: String {
        switch current {
        case .japanese: return "このMacをFreeに戻すだけです。有料プランの課金は解約されません。"
        case .english: return "This only reverts this Mac to Free. It does NOT cancel your paid subscription."
        case .chinese: return "仅将此 Mac 恢复为免费版，不会取消您的付费订阅。"
        }
    }

    /// 有料プランの解約セクション見出し
    static var cancelPlanTitle: String {
        switch current {
        case .japanese: return "有料プランを解約する"
        case .english: return "Cancel paid plan"
        case .chinese: return "取消付费套餐"
        }
    }

    /// 解約手順の説明
    static var cancelPlanNote: String {
        switch current {
        case .japanese: return "解約はStripeで行います。ご購入時の確認メール内の「サブスクリプションを管理」リンクから解約できます。解約後も、次回更新日まではProのままご利用いただけます。"
        case .english: return "Cancellation is handled by Stripe. Use the “Manage subscription” link in your purchase receipt email. You keep Pro until the end of the current period."
        case .chinese: return "取消由 Stripe 处理。请使用购买确认邮件中的\u{201C}管理订阅\u{201D}链接。取消后在本计费周期结束前仍可使用 Pro。"
        }
    }

    static var usageStatus: String {
        switch current {
        case .japanese: return "利用状況"
        case .english: return "Usage"
        case .chinese: return "使用状况"
        }
    }

    static var autoOptimizeThreshold: String {
        switch current {
        case .japanese: return "自動最適化しきい値"
        case .english: return "Auto-optimize threshold"
        case .chinese: return "自动优化阈值"
        }
    }

    static var autoOptimizeThresholdDesc: String {
        switch current {
        case .japanese: return "メモリ使用率がこの値を超えると、最適化の提案を自動表示します"
        case .english: return "When memory usage exceeds this value, optimization suggestions are shown automatically"
        case .chinese: return "当内存使用率超过此值时，将自动显示优化建议"
        }
    }

    static var memoryMonitoring: String {
        switch current {
        case .japanese: return "メモリ監視"
        case .english: return "Memory Monitoring"
        case .chinese: return "内存监控"
        }
    }

    static var monitorStoragePressure: String {
        switch current {
        case .japanese: return "ストレージ圧迫を監視する"
        case .english: return "Monitor storage pressure"
        case .chinese: return "监控存储空间不足"
        }
    }

    static var pressureUsagePercent: String {
        switch current {
        case .japanese: return "圧迫とみなす使用率"
        case .english: return "Usage considered \"low\""
        case .chinese: return "视为不足的使用率"
        }
    }

    static var pressureFreeSpace: String {
        switch current {
        case .japanese: return "圧迫とみなす空き容量"
        case .english: return "Free space considered \"low\""
        case .chinese: return "视为不足的可用空间"
        }
    }

    static func lessThanGB(_ gb: Int) -> String {
        switch current {
        case .japanese: return "\(gb)GB 未満"
        case .english: return "Under \(gb)GB"
        case .chinese: return "低于 \(gb)GB"
        }
    }

    static var pressureRuleDesc: String {
        switch current {
        case .japanese: return "使用率か空き容量のどちらかが上記に達すると圧迫とみなします。"
        case .english: return "Space is considered low when either the usage rate or free space reaches the above."
        case .chinese: return "当使用率或可用空间任一达到上述条件时，即视为空间不足。"
        }
    }

    static var autoFreeOnPressure: String {
        switch current {
        case .japanese: return "圧迫時は自動で空ける（通知のみ）"
        case .english: return "Auto-free space when low (notify only)"
        case .chinese: return "空间不足时自动清理（仅通知）"
        }
    }

    static var autoFreeOnDesc: String {
        switch current {
        case .japanese: return "ストレージが圧迫したら、リスクのないキャッシュ/ログを自動削除し、結果を通知でお知らせします。"
        case .english: return "When storage runs low, risk-free caches/logs are deleted automatically and the result is shown in a notification."
        case .chinese: return "当存储空间不足时，自动删除无风险的缓存/日志，并通过通知告知结果。"
        }
    }

    static var autoFreeOffDesc: String {
        switch current {
        case .japanese: return "ストレージが圧迫したら、何を消すか・安全度を提示して、ワンボタンで空けられるよう提案します。"
        case .english: return "When storage runs low, we show what to delete and its safety level so you can free space with one tap."
        case .chinese: return "当存储空间不足时，会提示删除内容及其安全程度，让您一键释放空间。"
        }
    }

    static var storageAutoGuard: String {
        switch current {
        case .japanese: return "ストレージ自動ガード"
        case .english: return "Storage Auto Guard"
        case .chinese: return "存储自动防护"
        }
    }

    static var browserAutomationNote: String {
        switch current {
        case .japanese: return "Chrome/Safariのタブ分析には「オートメーション」権限が必要です（初回に許可を求められます）。"
        case .english: return "Chrome/Safari tab analysis requires the \"Automation\" permission (you'll be asked to allow it the first time)."
        case .chinese: return "分析 Chrome/Safari 标签需要「自动化」权限（首次会请求授权）。"
        }
    }

    static var openAutomationSettings: String {
        switch current {
        case .japanese: return "オートメーション設定を開く"
        case .english: return "Open Automation settings"
        case .chinese: return "打开自动化设置"
        }
    }

    static var browserIntegration: String {
        switch current {
        case .japanese: return "ブラウザ連携"
        case .english: return "Browser Integration"
        case .chinese: return "浏览器集成"
        }
    }

    static var runInterval: String {
        switch current {
        case .japanese: return "実行間隔"
        case .english: return "Run interval"
        case .chinese: return "运行间隔"
        }
    }

    static func minutes(_ n: Int) -> String {
        switch current {
        case .japanese: return "\(n)分"
        case .english: return "\(n) min"
        case .chinese: return "\(n)分钟"
        }
    }

    static func hours(_ n: Int) -> String {
        switch current {
        case .japanese: return "\(n)時間"
        case .english: return "\(n) hr"
        case .chinese: return "\(n)小时"
        }
    }

    static var onlyWhenIdle: String {
        switch current {
        case .japanese: return "ユーザーがアイドル時のみ実行"
        case .english: return "Run only when idle"
        case .chinese: return "仅在空闲时运行"
        }
    }

    static func nextRun(_ time: String) -> String {
        switch current {
        case .japanese: return "次回実行予定: \(time)"
        case .english: return "Next run: \(time)"
        case .chinese: return "下次运行: \(time)"
        }
    }

    static var aboutSafety: String {
        switch current {
        case .japanese: return "安全性について"
        case .english: return "About Safety"
        case .chinese: return "关于安全性"
        }
    }

    static var scheduleSafetyDesc: String {
        switch current {
        case .japanese: return "自動最適化は、過去に3回以上手動で最適化したアプリのみを対象とします。業務中のアプリは自動で終了しません。夜間(23〜7時)は実行しません。"
        case .english: return "Auto optimization only targets apps you've manually optimized at least 3 times. Apps in active use are never quit automatically. It does not run at night (11 PM–7 AM)."
        case .chinese: return "自动优化仅针对您手动优化过 3 次以上的应用。正在使用的应用不会被自动退出。夜间（23–7 点）不运行。"
        }
    }

    static var scheduleProLock: String {
        switch current {
        case .japanese: return "スケジュール自動最適化はPro機能です"
        case .english: return "Scheduled auto optimization is a Pro feature"
        case .chinese: return "定时自动优化是 Pro 功能"
        }
    }

    static var scheduleProLockDesc: String {
        switch current {
        case .japanese: return "Proにアップグレードすると、定期的な自動最適化を設定できます"
        case .english: return "Upgrade to Pro to set up periodic automatic optimization"
        case .chinese: return "升级到 Pro 即可设置定期自动优化"
        }
    }

    static var checkOnLicenseTab: String {
        switch current {
        case .japanese: return "ライセンスタブで確認"
        case .english: return "View on License tab"
        case .chinese: return "在许可证选项卡查看"
        }
    }

    static var aiLearningData: String {
        switch current {
        case .japanese: return "AI学習データ"
        case .english: return "AI Learning Data"
        case .chinese: return "AI 学习数据"
        }
    }

    static var aiLearningDataDesc: String {
        switch current {
        case .japanese: return "アプリの使用パターンを学習して、より適切な最適化提案を行います。データはローカルにのみ保存されます。"
        case .english: return "Learns your app usage patterns to make better optimization suggestions. Data is stored locally only."
        case .chinese: return "学习应用的使用模式，以提供更合适的优化建议。数据仅保存在本地。"
        }
    }

    static var resetLearningData: String {
        switch current {
        case .japanese: return "学習データをリセット"
        case .english: return "Reset learning data"
        case .chinese: return "重置学习数据"
        }
    }

    static var aiLearning: String {
        switch current {
        case .japanese: return "AI学習"
        case .english: return "AI Learning"
        case .chinese: return "AI 学习"
        }
    }

    static var enableNotifications: String {
        switch current {
        case .japanese: return "通知を有効にする"
        case .english: return "Enable notifications"
        case .chinese: return "启用通知"
        }
    }

    static var notifyThreshold: String {
        switch current {
        case .japanese: return "通知しきい値"
        case .english: return "Notification threshold"
        case .chinese: return "通知阈值"
        }
    }

    static var notifyThresholdDesc: String {
        switch current {
        case .japanese: return "メモリ使用率がこの値を超えると通知を表示します"
        case .english: return "Shows a notification when memory usage exceeds this value"
        case .chinese: return "当内存使用率超过此值时显示通知"
        }
    }

    static var notificationSettings: String {
        switch current {
        case .japanese: return "通知設定"
        case .english: return "Notification Settings"
        case .chinese: return "通知设置"
        }
    }

    static func appVersion(_ v: String) -> String {
        switch current {
        case .japanese: return "バージョン \(v)"
        case .english: return "Version \(v)"
        case .chinese: return "版本 \(v)"
        }
    }

    static var aboutDescription: String {
        switch current {
        case .japanese: return "AIがあなたのMacのメモリとストレージを賢く最適化します。\n11種類のAI分析で、使用パターンを学習してより適切な提案を行います。"
        case .english: return "AI intelligently optimizes your Mac's memory and storage.\nWith 11 types of AI analysis, it learns your usage patterns to make better suggestions."
        case .chinese: return "AI 智能优化你的 Mac 内存和存储。\n通过 11 种 AI 分析，学习你的使用模式以提供更合适的建议。"
        }
    }

    static var reportBug: String {
        switch current {
        case .japanese: return "不具合・バグを報告"
        case .english: return "Report a Bug"
        case .chinese: return "报告问题・错误"
        }
    }

    static var reportBugDesc: String {
        switch current {
        case .japanese: return "環境情報（バージョン・macOS）を添えてメールが開きます"
        case .english: return "Opens an email with environment info (version, macOS) attached"
        case .chinese: return "将打开附带环境信息（版本・macOS）的邮件"
        }
    }

    static var bugReportSubject: String {
        switch current {
        case .japanese: return "【不具合報告】AI Mac Optimizer"
        case .english: return "[Bug Report] AI Mac Optimizer"
        case .chinese: return "【问题报告】AI Mac Optimizer"
        }
    }

    static func bugReportBody(osVersion: String, arch: String, version: String) -> String {
        switch current {
        case .japanese: return """
            （ここに不具合の内容・再現手順・期待する動作をご記入ください）



            --- 環境情報（自動入力。消さないでください） ---
            アプリ: AI Mac Optimizer \(version)
            macOS: \(osVersion)
            機種: \(arch)
            """
        case .english: return """
            (Please describe the issue, steps to reproduce, and expected behavior here)



            --- Environment info (auto-filled. Please do not remove) ---
            App: AI Mac Optimizer \(version)
            macOS: \(osVersion)
            Model: \(arch)
            """
        case .chinese: return """
            （请在此填写问题内容、复现步骤和期望行为）



            --- 环境信息（自动填写。请勿删除） ---
            应用: AI Mac Optimizer \(version)
            macOS: \(osVersion)
            机型: \(arch)
            """
        }
    }

    // MARK: - Notifications
    static var notifyMemoryTitle: String {
        switch current {
        case .japanese: return "メモリ警告"
        case .english: return "Memory Alert"
        case .chinese: return "内存警告"
        }
    }

    static func notifyMemoryBody(percent: Int) -> String {
        switch current {
        case .japanese: return "メモリ使用率が\(percent)%に達しました"
        case .english: return "Memory usage has reached \(percent)%"
        case .chinese: return "内存使用率已达到 \(percent)%"
        }
    }

    static var notifyMemorySuggestion: String {
        switch current {
        case .japanese: return "不要なアプリを終了するか、メモリタブから最適化してください"
        case .english: return "Quit unneeded apps or optimize from the Memory tab"
        case .chinese: return "请关闭不需要的应用，或从内存选项卡进行优化"
        }
    }

    static var notifyDiskTitle: String {
        switch current {
        case .japanese: return "ストレージ空き容量警告"
        case .english: return "Low Storage Alert"
        case .chinese: return "存储空间不足警告"
        }
    }

    static func notifyDiskBody(freeGB: String) -> String {
        switch current {
        case .japanese: return "ストレージ空き容量が\(freeGB)GBです"
        case .english: return "Free storage is \(freeGB)GB"
        case .chinese: return "存储可用空间为 \(freeGB)GB"
        }
    }

    static var notifyDiskSuggestion: String {
        switch current {
        case .japanese: return "ストレージタブで不要ファイルを整理してください"
        case .english: return "Clean up unneeded files from the Storage tab"
        case .chinese: return "请在存储选项卡中整理不需要的文件"
        }
    }

    // MARK: - Battery Condition (display + color)
    static var batteryConditionNormal: String {
        switch current {
        case .japanese: return "正常"
        case .english: return "Normal"
        case .chinese: return "正常"
        }
    }

    static var batteryConditionGood: String {
        switch current {
        case .japanese: return "良好"
        case .english: return "Good"
        case .chinese: return "良好"
        }
    }

    static var batteryConditionWarning: String {
        switch current {
        case .japanese: return "警告"
        case .english: return "Warning"
        case .chinese: return "警告"
        }
    }

    static var batteryConditionReplace: String {
        switch current {
        case .japanese: return "交換推奨"
        case .english: return "Replace soon"
        case .chinese: return "建议更换"
        }
    }

    static var batteryConditionUnknown: String {
        switch current {
        case .japanese: return "不明"
        case .english: return "Unknown"
        case .chinese: return "未知"
        }
    }

    static var batteryConditionDesktop: String {
        switch current {
        case .japanese: return "デスクトップ"
        case .english: return "Desktop"
        case .chinese: return "台式机"
        }
    }

    static var batteryCalculating: String {
        switch current {
        case .japanese: return "計算中"
        case .english: return "Calculating"
        case .chinese: return "计算中"
        }
    }

    static func batteryTimeHM(hours: Int, minutes: Int) -> String {
        switch current {
        case .japanese: return String(format: "%d時間 %d分", hours, minutes)
        case .english: return String(format: "%dh %dm", hours, minutes)
        case .chinese: return String(format: "%d小时 %d分", hours, minutes)
        }
    }

    static func batteryTimeM(minutes: Int) -> String {
        switch current {
        case .japanese: return String(format: "%d分", minutes)
        case .english: return String(format: "%dm", minutes)
        case .chinese: return String(format: "%d分", minutes)
        }
    }

    // MARK: - Storage Category (localized display)
    static var storageCacheName: String {
        switch current {
        case .japanese: return "キャッシュ"
        case .english: return "Cache"
        case .chinese: return "缓存"
        }
    }

    static var storageLogName: String {
        switch current {
        case .japanese: return "ログ"
        case .english: return "Logs"
        case .chinese: return "日志"
        }
    }

    static var storageInstallerName: String {
        switch current {
        case .japanese: return "インストーラー"
        case .english: return "Installers"
        case .chinese: return "安装程序"
        }
    }

    static var storageLargeFileName: String {
        switch current {
        case .japanese: return "大容量ファイル"
        case .english: return "Large Files"
        case .chinese: return "大文件"
        }
    }

    static var storageDownloadName: String {
        switch current {
        case .japanese: return "ダウンロード"
        case .english: return "Downloads"
        case .chinese: return "下载"
        }
    }

    static var storageICloudCandidateName: String {
        switch current {
        case .japanese: return "iCloud退避候補"
        case .english: return "iCloud Offload"
        case .chinese: return "iCloud 卸载候选"
        }
    }

    // MARK: - Storage Action (localized display)
    static var storageActionDelete: String {
        switch current {
        case .japanese: return "削除"
        case .english: return "Delete"
        case .chinese: return "删除"
        }
    }

    static var storageActionMoveToTrash: String {
        switch current {
        case .japanese: return "ゴミ箱に移動"
        case .english: return "Move to Trash"
        case .chinese: return "移至废纸篓"
        }
    }

    static var storageActionMoveToICloud: String {
        switch current {
        case .japanese: return "iCloudに退避"
        case .english: return "Move to iCloud"
        case .chinese: return "移至 iCloud"
        }
    }

    // MARK: - Diagnosis Category (localized display)
    static var diagCategoryCPU: String {
        switch current {
        case .japanese: return "CPU負荷"
        case .english: return "CPU Load"
        case .chinese: return "CPU 负载"
        }
    }

    static var diagCategoryMemory: String {
        switch current {
        case .japanese: return "メモリ"
        case .english: return "Memory"
        case .chinese: return "内存"
        }
    }

    static var diagCategoryDisk: String {
        switch current {
        case .japanese: return "ストレージ"
        case .english: return "Storage"
        case .chinese: return "存储"
        }
    }

    static var diagCategoryICloud: String {
        switch current {
        case .japanese: return "iCloud同期"
        case .english: return "iCloud Sync"
        case .chinese: return "iCloud 同步"
        }
    }

    static var diagCategorySecurity: String {
        switch current {
        case .japanese: return "セキュリティソフト"
        case .english: return "Security Software"
        case .chinese: return "安全软件"
        }
    }

    static var diagCategoryDevTools: String {
        switch current {
        case .japanese: return "開発ツール"
        case .english: return "Dev Tools"
        case .chinese: return "开发工具"
        }
    }

    static var diagCategoryBrowserApp: String {
        switch current {
        case .japanese: return "ブラウザ・アプリ"
        case .english: return "Browsers & Apps"
        case .chinese: return "浏览器・应用"
        }
    }

    static var diagCategoryLoginItems: String {
        switch current {
        case .japanese: return "ログイン項目"
        case .english: return "Login Items"
        case .chinese: return "登录项"
        }
    }

    static var diagCategoryComposite: String {
        switch current {
        case .japanese: return "総合スコア"
        case .english: return "Overall Score"
        case .chinese: return "综合评分"
        }
    }

    // MARK: - Diagnosis Severity (unified vocabulary)
    static var diagSeverityCritical: String {
        switch current {
        case .japanese: return "危険"
        case .english: return "Critical"
        case .chinese: return "严重"
        }
    }

    static var diagSeverityWarning: String {
        switch current {
        case .japanese: return "注意"
        case .english: return "Warning"
        case .chinese: return "注意"
        }
    }

    static var diagSeverityInfo: String {
        switch current {
        case .japanese: return "情報"
        case .english: return "Info"
        case .chinese: return "信息"
        }
    }

    static var diagSeverityGood: String {
        switch current {
        case .japanese: return "良好"
        case .english: return "Good"
        case .chinese: return "良好"
        }
    }

    // MARK: - Diagnosis Fix Action (localized button labels)
    static var fixPurgeRAM: String {
        switch current {
        case .japanese: return "RAMパージ実行"
        case .english: return "Purge RAM"
        case .chinese: return "清理 RAM"
        }
    }

    static var fixQuitApp: String {
        switch current {
        case .japanese: return "アプリを終了"
        case .english: return "Quit App"
        case .chinese: return "退出应用"
        }
    }

    static var fixClearCache: String {
        switch current {
        case .japanese: return "キャッシュ削除"
        case .english: return "Clear Cache"
        case .chinese: return "清除缓存"
        }
    }

    static var fixClearDerivedData: String {
        switch current {
        case .japanese: return "DerivedData削除"
        case .english: return "Clear DerivedData"
        case .chinese: return "清除 DerivedData"
        }
    }

    static var fixClearBrowserCache: String {
        switch current {
        case .japanese: return "ブラウザキャッシュ削除"
        case .english: return "Clear Browser Cache"
        case .chinese: return "清除浏览器缓存"
        }
    }

    static var fixFlushDNS: String {
        switch current {
        case .japanese: return "DNSフラッシュ"
        case .english: return "Flush DNS"
        case .chinese: return "刷新 DNS"
        }
    }

    static var fixOpenSystemSettings: String {
        switch current {
        case .japanese: return "システム設定を開く"
        case .english: return "Open System Settings"
        case .chinese: return "打开系统设置"
        }
    }

    static var fixOpenFontBook: String {
        switch current {
        case .japanese: return "Font Bookを開く"
        case .english: return "Open Font Book"
        case .chinese: return "打开字体册"
        }
    }

    // MARK: - Risk levels (shared vocabulary for 高/中/低)
    static var riskHigh: String {
        switch current {
        case .japanese: return "高"
        case .english: return "High"
        case .chinese: return "高"
        }
    }

    static var riskMid: String {
        switch current {
        case .japanese: return "中"
        case .english: return "Medium"
        case .chinese: return "中"
        }
    }

    static var riskLo: String {
        switch current {
        case .japanese: return "低"
        case .english: return "Low"
        case .chinese: return "低"
        }
    }

    // MARK: - Cleanup Safety (localized display)
    static var cleanupSafetySafe: String {
        switch current {
        case .japanese: return "安全"
        case .english: return "Safe"
        case .chinese: return "安全"
        }
    }

    static var cleanupSafetyCaution: String {
        switch current {
        case .japanese: return "やや注意"
        case .english: return "Caution"
        case .chinese: return "略需注意"
        }
    }

    // MARK: - AI Provider (localized display)
    static var providerLocal: String {
        switch current {
        case .japanese: return "ローカル解析（無料）"
        case .english: return "Local Analysis (Free)"
        case .chinese: return "本地分析（免费）"
        }
    }

    static var providerAppleOnDevice: String {
        switch current {
        case .japanese: return "オンデバイスAI（無料）"
        case .english: return "On-device AI (Free)"
        case .chinese: return "设备端 AI（免费）"
        }
    }

    // MARK: - Smart Advisor (suggestion titles & short descriptions)
    static func estimatedFreeMB(_ mb: Int) -> String {
        switch current {
        case .japanese: return "推定 \(mb) MB 解放可能"
        case .english: return "Approx. \(mb) MB can be freed"
        case .chinese: return "预计可释放 \(mb) MB"
        }
    }

    static func suggestCloseChromeTabs(count: Int) -> String {
        switch current {
        case .japanese: return "不要なChromeタブを閉じる (\(count)個)"
        case .english: return "Close unneeded Chrome tabs (\(count))"
        case .chinese: return "关闭多余的 Chrome 标签 (\(count)个)"
        }
    }

    static func suggestCloseSafariTabs(count: Int) -> String {
        switch current {
        case .japanese: return "不要なSafariタブを閉じる (\(count)個)"
        case .english: return "Close unneeded Safari tabs (\(count))"
        case .chinese: return "关闭多余的 Safari 标签 (\(count)个)"
        }
    }

    static func suggestQuitBackgroundApps(count: Int) -> String {
        switch current {
        case .japanese: return "バックグラウンドアプリを終了 (\(count)個)"
        case .english: return "Quit background apps (\(count))"
        case .chinese: return "退出后台应用 (\(count)个)"
        }
    }

    static func suggestRestartApp(_ name: String) -> String {
        switch current {
        case .japanese: return "\(name) を再起動"
        case .english: return "Restart \(name)"
        case .chinese: return "重启 \(name)"
        }
    }

    static func suggestAppMemoryUsing(_ formatted: String) -> String {
        switch current {
        case .japanese: return "\(formatted) 使用中"
        case .english: return "Using \(formatted)"
        case .chinese: return "正在使用 \(formatted)"
        }
    }

    static func suggestClearBrowserCache(count: Int) -> String {
        switch current {
        case .japanese: return "ブラウザキャッシュを削除 (\(count)ブラウザ)"
        case .english: return "Clear browser cache (\(count) browsers)"
        case .chinese: return "清除浏览器缓存 (\(count)个浏览器)"
        }
    }

    static func suggestHeavyChromeExtensions(count: Int) -> String {
        switch current {
        case .japanese: return "重いChrome拡張機能 (\(count)個)"
        case .english: return "Heavy Chrome extensions (\(count))"
        case .chinese: return "占用较高的 Chrome 扩展 (\(count)个)"
        }
    }

    static func suggestRuntimeMemory(_ mb: Int) -> String {
        switch current {
        case .japanese: return "推定ランタイムメモリ \(mb) MB"
        case .english: return "Est. runtime memory \(mb) MB"
        case .chinese: return "预计运行时内存 \(mb) MB"
        }
    }

    static func suggestReviewLoginItems(count: Int) -> String {
        switch current {
        case .japanese: return "ログイン項目を見直し (\(count)個)"
        case .english: return "Review login items (\(count))"
        case .chinese: return "检查登录项 (\(count)个)"
        }
    }

    static func suggestLoginItemsUsing(_ mb: Int) -> String {
        switch current {
        case .japanese: return "起動時に \(mb) MB 使用"
        case .english: return "Uses \(mb) MB at startup"
        case .chinese: return "启动时占用 \(mb) MB"
        }
    }

    static var suggestClearTmpFiles: String {
        switch current {
        case .japanese: return "一時ファイルを削除"
        case .english: return "Delete temporary files"
        case .chinese: return "删除临时文件"
        }
    }

    static var suggestClearDNSCache: String {
        switch current {
        case .japanese: return "DNSキャッシュをクリア"
        case .english: return "Clear DNS cache"
        case .chinese: return "清除 DNS 缓存"
        }
    }

    static func suggestSwapHigh(_ formatted: String) -> String {
        switch current {
        case .japanese: return "⚠️ Swap使用量が高い (\(formatted))"
        case .english: return "⚠️ High swap usage (\(formatted))"
        case .chinese: return "⚠️ 交换空间使用较高 (\(formatted))"
        }
    }

    static var suggestSwapHighDesc: String {
        switch current {
        case .japanese: return "Swapが多いと動作が遅くなります。下記の高メモリアプリを終了するとメモリが空きSwapが減ります（チェックして実行）"
        case .english: return "High swap usage slows things down. Quitting the high-memory apps below frees memory and reduces swap (check and run)."
        case .chinese: return "交换空间过多会导致运行变慢。退出下方的高内存应用可释放内存并减少交换（勾选后执行）。"
        }
    }

    // MARK: - Deep Diagnosis progress steps
    static var diagStepCPU: String {
        switch current {
        case .japanese: return "CPU負荷を分析中..."
        case .english: return "Analyzing CPU load..."
        case .chinese: return "正在分析 CPU 负载..."
        }
    }

    static var diagStepMemory: String {
        switch current {
        case .japanese: return "メモリ状態を分析中..."
        case .english: return "Analyzing memory..."
        case .chinese: return "正在分析内存状态..."
        }
    }

    static var diagStepDisk: String {
        switch current {
        case .japanese: return "ストレージ容量を分析中..."
        case .english: return "Analyzing storage..."
        case .chinese: return "正在分析存储容量..."
        }
    }

    static var diagStepICloud: String {
        switch current {
        case .japanese: return "iCloud同期を確認中..."
        case .english: return "Checking iCloud sync..."
        case .chinese: return "正在检查 iCloud 同步..."
        }
    }

    static var diagStepSecurity: String {
        switch current {
        case .japanese: return "セキュリティソフトを確認中..."
        case .english: return "Checking security software..."
        case .chinese: return "正在检查安全软件..."
        }
    }

    static var diagStepDevTools: String {
        switch current {
        case .japanese: return "開発ツールを確認中..."
        case .english: return "Checking dev tools..."
        case .chinese: return "正在检查开发工具..."
        }
    }

    static var diagStepBrowserApps: String {
        switch current {
        case .japanese: return "ブラウザ・アプリを分析中..."
        case .english: return "Analyzing browsers & apps..."
        case .chinese: return "正在分析浏览器和应用..."
        }
    }

    static var diagStepLoginItems: String {
        switch current {
        case .japanese: return "ログイン項目を確認中..."
        case .english: return "Checking login items..."
        case .chinese: return "正在检查登录项..."
        }
    }

    static var diagStepScore: String {
        switch current {
        case .japanese: return "総合スコアを算出中..."
        case .english: return "Calculating overall score..."
        case .chinese: return "正在计算综合评分..."
        }
    }
}
