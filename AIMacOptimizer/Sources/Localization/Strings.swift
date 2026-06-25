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
        case .japanese: return "逼迫"
        case .english: return "Critical"
        case .chinese: return "紧张"
        }
    }

    // MARK: - Sections
    static var memoryUsage: String {
        switch current {
        case .japanese: return "メモリ使用状況"
        case .english: return "Memory Usage"
        case .chinese: return "内存使用"
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
}
