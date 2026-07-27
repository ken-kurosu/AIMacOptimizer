import Foundation

/// 実測した最適化結果と診断課題の再発だけを永続化するローカル監査ログ。
/// 推定値は保存せず、累積解放量には実行後に計測できた値だけを加算する。
final class OptimizationAuditStore {
    static let shared = OptimizationAuditStore()

    struct ExecutionRecord: Codable, Identifiable {
        let id: UUID
        let date: Date
        let source: String
        let action: String
        let succeeded: Bool
        let freedDiskMB: Double
        let freedMemoryMB: Double
    }

    struct RecurrenceRecord: Codable, Identifiable {
        let id: UUID
        let issueKey: String
        let title: String
        let days: Int
        let detectedAt: Date
    }

    private struct State: Codable {
        var executions: [ExecutionRecord] = []
        var cumulativeFreedDiskMB: Double = 0
        var lastSeenByIssue: [String: Date] = [:]
        var activeIssueKeys: Set<String> = []
        var recurrences: [RecurrenceRecord] = []
    }

    private let lock = NSLock()
    private let fileURL: URL
    private var state: State

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AIMacOptimizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("optimization_audit.json")
        if let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode(State.self, from: data) {
            state = decoded
        } else {
            state = State()
        }
    }

    var cumulativeFreedDiskMB: Double {
        lock.withLock { state.cumulativeFreedDiskMB }
    }

    var lastExecution: ExecutionRecord? {
        lock.withLock { state.executions.last }
    }

    var recentRecurrences: [RecurrenceRecord] {
        lock.withLock { Array(state.recurrences.suffix(10)).reversed() }
    }

    func recordExecution(source: String, action: String, succeeded: Bool,
                         freedDiskMB: Double = 0, freedMemoryMB: Double = 0) {
        let measuredDiskMB = max(0, freedDiskMB)
        lock.withLock {
            state.executions.append(ExecutionRecord(
                id: UUID(), date: Date(), source: source, action: action,
                succeeded: succeeded, freedDiskMB: measuredDiskMB,
                freedMemoryMB: max(0, freedMemoryMB)
            ))
            state.cumulativeFreedDiskMB += measuredDiskMB
            state.executions = Array(state.executions.suffix(500))
            saveLocked()
        }
    }

    /// 警告/重大項目が一度消えた後に再登場したときだけ「再発」として記録する。
    func recordDiagnosis(_ report: DiagnosisReport) {
        let significant = report.findings.filter { $0.severity == .warning || $0.severity == .critical }
        var current: [String: String] = [:]
        for finding in significant { current[issueKey(for: finding)] = finding.title }
        let now = report.timestamp

        lock.withLock {
            for (key, title) in current where !state.activeIssueKeys.contains(key) {
                if let previous = state.lastSeenByIssue[key] {
                    let days = max(1, Calendar.current.dateComponents([.day], from: previous, to: now).day ?? 1)
                    state.recurrences.append(RecurrenceRecord(
                        id: UUID(), issueKey: key, title: title, days: days, detectedAt: now
                    ))
                }
            }
            for key in current.keys { state.lastSeenByIssue[key] = now }
            state.activeIssueKeys = Set(current.keys)
            state.recurrences = Array(state.recurrences.suffix(100))
            saveLocked()
        }
    }

    private func issueKey(for finding: DiagnosisFinding) -> String {
        let stableTarget = finding.rawData["path"]
            ?? finding.rawData["process"]
            ?? (finding.fixTarget.isEmpty ? nil : finding.fixTarget)
        if let stableTarget {
            return "\(finding.category.rawValue)|\(finding.fixAction.rawValue)|\(stableTarget)"
        }
        let normalizedTitle = finding.title.replacingOccurrences(
            of: #"[0-9]+(?:[.,][0-9]+)?"#, with: "#", options: .regularExpression
        )
        return "\(finding.category.rawValue)|\(normalizedTitle)"
    }

    private func saveLocked() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
