import Foundation

/// Represents a Chrome browser tab
struct ChromeTab: Identifiable {
    let id: Int
    let title: String
    let url: String
    let windowIndex: Int
    let tabIndex: Int
    var category: TabCategory = .unknown

    var domain: String {
        guard let url = URL(string: url) else { return "" }
        return url.host ?? ""
    }
}

/// AI-suggested category for a Chrome tab
enum TabCategory: String, CaseIterable {
    case closeable = "閉じて良い"
    case working = "業務中"
    case needsReview = "要確認"
    case unknown = "未分類"

    var emoji: String {
        switch self {
        case .closeable: return "🔴"
        case .working: return "🟢"
        case .needsReview: return "🟡"
        case .unknown: return "⚪"
        }
    }
}

/// Suggestion from the smart advisor
struct OptimizationSuggestion: Identifiable {
    let id = UUID()
    let type: SuggestionType
    let title: String
    let description: String
    let estimatedSavingMB: Double
    let action: () async -> Bool
    /// Detailed sub-items the user can expand and select/deselect
    var detailItems: [SuggestionDetailItem]

    init(type: SuggestionType, title: String, description: String,
         estimatedSavingMB: Double, detailItems: [SuggestionDetailItem] = [],
         action: @escaping () async -> Bool) {
        self.type = type
        self.title = title
        self.description = description
        self.estimatedSavingMB = estimatedSavingMB
        self.detailItems = detailItems
        self.action = action
    }

    var savingFormatted: String {
        if estimatedSavingMB >= 1024 {
            return String(format: "%.1f GB", estimatedSavingMB / 1024)
        }
        return String(format: "%.0f MB", estimatedSavingMB)
    }
}

/// A selectable sub-item within a suggestion (e.g. individual tab, file)
struct SuggestionDetailItem: Identifiable {
    let id = UUID()
    let name: String
    let detail: String       // short reason or description
    let sizeMB: Double
    var isSelected: Bool = true
    var isRecommended: Bool = false  // AI recommends removing this

    var sizeFormatted: String {
        if sizeMB >= 1024 {
            return String(format: "%.1f GB", sizeMB / 1024)
        }
        return String(format: "%.0f MB", sizeMB)
    }
}

enum SuggestionType: String {
    case closeTab = "タブを閉じる"
    case closeSafariTab = "Safariタブを閉じる"
    case quitApp = "アプリを終了"
    case restartApp = "アプリを再起動"
    case purgeRAM = "RAMキャッシュをパージ"
    case clearCache = "キャッシュを削除"
    case flushDNS = "DNSキャッシュをフラッシュ"
    case flushFontCache = "フォントキャッシュをクリア"
    case clearTmpFiles = "一時ファイルを削除"
    case disableLoginItem = "ログイン項目を無効化"
    case swapWarning = "Swap使用量の警告"
    case clearBrowserCache = "ブラウザキャッシュを削除"
}
