import Foundation

// MARK: - Deep Diagnosis Result Model

/// Severity level for a diagnosis finding
enum DiagnosisSeverity: String, Codable, Comparable {
    case critical = "critical"
    case warning = "warning"
    case info = "info"
    case good = "good"

    var label: String {
        switch self {
        case .critical: return "危険"
        case .warning: return "注意"
        case .info: return "情報"
        case .good: return "良好"
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
    case disk = "ディスク"
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

    var buttonLabel: String {
        switch self {
        case .purgeRAM: return "RAMパージ実行"
        case .quitApp: return "アプリを終了"
        case .clearCache: return "キャッシュ削除"
        case .clearDerivedData: return "DerivedData削除"
        case .clearBrowserCache: return "ブラウザキャッシュ削除"
        case .flushDNS: return "DNSフラッシュ"
        case .openSystemSettings: return "システム設定を開く"
        case .openFontBook: return "Font Bookを開く"
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
        lines.append("システム: RAM \(systemSnapshot.totalRAM_MB)MB, ディスク空き \(systemSnapshot.diskFreeGB)GB/\(systemSnapshot.diskTotalGB)GB")
        lines.append("CPU Load Average: \(systemSnapshot.loadAverage)")
        lines.append("")

        for finding in findings.sorted(by: { $0.severity < $1.severity }) {
            lines.append("[\(finding.severity.label)] \(finding.category.rawValue): \(finding.title)")
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
