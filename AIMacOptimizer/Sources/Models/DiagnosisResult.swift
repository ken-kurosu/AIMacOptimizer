import Foundation

// MARK: - Deep Diagnosis Result Model

/// Severity level for a diagnosis finding
enum DiagnosisSeverity: String, Codable, Comparable {
    case critical = "critical"
    case warning = "warning"
    case info = "info"
    case good = "good"

    /// Localized display label (rawValue kept stable for Codable/comparison)
    var label: String {
        switch self {
        case .critical: return L10n.diagSeverityCritical
        case .warning: return L10n.diagSeverityWarning
        case .info: return L10n.diagSeverityInfo
        case .good: return L10n.diagSeverityGood
        }
    }

    var icon: String {
        switch self {
        case .critical: return "exclamationmark.triangle.fill"
        case .warning: return "exclamationmark.circle.fill"
        case .info: return "info.circle.fill"
        case .good: return "checkmark.circle.fill"
        }
    }

    private var sortOrder: Int {
        switch self {
        case .critical: return 0
        case .warning: return 1
        case .info: return 2
        case .good: return 3
        }
    }

    static func < (lhs: DiagnosisSeverity, rhs: DiagnosisSeverity) -> Bool {
        lhs.sortOrder < rhs.sortOrder
    }
}

/// Category of diagnosis engine
enum DiagnosisCategory: String, Codable {
    case cpu = "CPU負荷"
    case memory = "メモリ"
    case disk = "ストレージ"
    case icloudSync = "iCloud同期"
    case securitySoftware = "セキュリティソフト"
    case devTools = "開発ツール"
    case browserApp = "ブラウザ・アプリ"
    case loginItems = "ログイン項目"
    case composite = "総合スコア"

    var icon: String {
        switch self {
        case .cpu: return "cpu"
        case .memory: return "memorychip"
        case .disk: return "internaldrive"
        case .icloudSync: return "icloud"
        case .securitySoftware: return "shield"
        case .devTools: return "hammer"
        case .browserApp: return "globe"
        case .loginItems: return "person.crop.circle"
        case .composite: return "gauge.with.dots.needle.33percent"
        }
    }

    /// Localized display name (rawValue kept stable for Codable)
    var localizedName: String {
        switch self {
        case .cpu: return L10n.diagCategoryCPU
        case .memory: return L10n.diagCategoryMemory
        case .disk: return L10n.diagCategoryDisk
        case .icloudSync: return L10n.diagCategoryICloud
        case .securitySoftware: return L10n.diagCategorySecurity
        case .devTools: return L10n.diagCategoryDevTools
        case .browserApp: return L10n.diagCategoryBrowserApp
        case .loginItems: return L10n.diagCategoryLoginItems
        case .composite: return L10n.diagCategoryComposite
        }
    }
}

/// Type of auto-fix action available for a finding
enum DiagnosisFixAction: String, Codable {
    case purgeRAM = "purge_ram"
    case quitApp = "quit_app"
    case clearCache = "clear_cache"
    case clearDerivedData = "clear_derived_data"
    case clearBrowserCache = "clear_browser_cache"
    case flushDNS = "flush_dns"
    case openSystemSettings = "open_system_settings"
    case openFontBook = "open_font_book"
    case none = "none"

    /// Localized button label (rawValue kept stable for Codable)
    var buttonLabel: String {
        switch self {
        case .purgeRAM: return L10n.fixPurgeRAM
        case .quitApp: return L10n.fixQuitApp
        case .clearCache: return L10n.fixClearCache
        case .clearDerivedData: return L10n.fixClearDerivedData
        case .clearBrowserCache: return L10n.fixClearBrowserCache
        case .flushDNS: return L10n.fixFlushDNS
        case .openSystemSettings: return L10n.fixOpenSystemSettings
        case .openFontBook: return L10n.fixOpenFontBook
        case .none: return ""
        }
    }

    var icon: String {
        switch self {
        case .purgeRAM: return "bolt.fill"
        case .quitApp: return "xmark.circle.fill"
        case .clearCache, .clearDerivedData, .clearBrowserCache: return "trash.fill"
        case .flushDNS: return "arrow.clockwise"
        case .openSystemSettings, .openFontBook: return "gear"
        case .none: return ""
        }
    }

    /// リスクのある操作か（true の場合「全て修復」では自動実行せず個別承認を求める）。
    /// アプリ/プロセスの終了は未保存データ消失などの恐れがあるため高リスク扱い。
    var isRisky: Bool {
        switch self {
        case .quitApp: return true
        default: return false
        }
    }
}

/// A single finding from a diagnosis engine
struct DiagnosisFinding: Identifiable, Codable {
    let id: UUID
    let category: DiagnosisCategory
    let severity: DiagnosisSeverity
    let title: String
    let detail: String
    /// Actionable suggestion (what the user can do)
    let suggestion: String
    /// Can this be auto-fixed by the app?
    let isAutoFixable: Bool
    /// The type of auto-fix action available
    let fixAction: DiagnosisFixAction
    /// Target for the fix (e.g. app name, cache path)
    let fixTarget: String
    /// Key-value data for AI chat context
    let rawData: [String: String]

    init(category: DiagnosisCategory, severity: DiagnosisSeverity, title: String,
         detail: String, suggestion: String, isAutoFixable: Bool = false,
         fixAction: DiagnosisFixAction = .none, fixTarget: String = "",
         rawData: [String: String] = [:]) {
        self.id = UUID()
        self.category = category
        self.severity = severity
        self.title = title
        self.detail = detail
        self.suggestion = suggestion
        self.isAutoFixable = isAutoFixable
        self.fixAction = fixAction
        self.fixTarget = fixTarget
        self.rawData = rawData
    }
}

/// Complete diagnosis report
struct DiagnosisReport: Codable {
    let timestamp: Date
    let findings: [DiagnosisFinding]
    let overallScore: Int // 0-100 (100 = perfect health)
    let systemSnapshot: SystemSnapshot

    var criticalCount: Int { findings.filter { $0.severity == .critical }.count }
    var warningCount: Int { findings.filter { $0.severity == .warning }.count }
    var overallSeverity: DiagnosisSeverity {
        if criticalCount > 0 { return .critical }
        if warningCount > 0 { return .warning }
        return .good
    }

    /// Generate a text summary for AI chat context injection
    func contextSummary() -> String {
        var lines: [String] = []
        lines.append("=== Mac診断レポート ===")
        lines.append("日時: \(ISO8601DateFormatter().string(from: timestamp))")
        lines.append("総合スコア: \(overallScore)/100")
        lines.append("システム: RAM \(systemSnapshot.totalRAM_MB)MB, ストレージ空き \(systemSnapshot.diskFreeGB)GB/\(systemSnapshot.diskTotalGB)GB")
        lines.append("CPU Load Average: \(systemSnapshot.loadAverage)")
        lines.append("")

        for finding in findings.sorted(by: { $0.severity < $1.severity }) {
            lines.append("[\(finding.severity.label)] \(finding.category.localizedName): \(finding.title)")
            lines.append("  詳細: \(finding.detail)")
            lines.append("  提案: \(finding.suggestion)")
            if !finding.rawData.isEmpty {
                for (k, v) in finding.rawData {
                    lines.append("  \(k): \(v)")
                }
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }
}

/// Snapshot of system state at diagnosis time
struct SystemSnapshot: Codable {
    let totalRAM_MB: Int
    let usedRAM_MB: Int
    let freeRAM_MB: Int
    let compressedRAM_MB: Int
    let swapUsedMB: Int
    let diskTotalGB: Int
    let diskFreeGB: Int
    let loadAverage: String
    let topProcesses: [String] // "ProcessName: 1234MB"
}
