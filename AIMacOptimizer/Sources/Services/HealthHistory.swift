import Foundation

/// 1時点の健康スナップショット（軽量に保つため最小限の指標のみ）
struct HealthSnapshot: Codable, Identifiable {
    let date: Date
    let memUsedPercent: Double
    let swapMB: Double
    let diskFreePercent: Double
    let loadAvg1: Double

    var id: Double { date.timeIntervalSince1970 }
}

/// メモリ/CPU/ディスクの健康指標を定期的に記録し、推移を提供する。
/// 既存の監視タイマーに相乗りし、10分間隔・14日上限のローカルJSON（数百KB）で保持。
/// Charts等の重いフレームワークは使わず、軽さを損なわない設計。
@MainActor
final class HealthHistory: ObservableObject {
    static let shared = HealthHistory()

    @Published private(set) var snapshots: [HealthSnapshot] = []

    private let fileURL: URL
    private let maxAgeSec: TimeInterval = 14 * 24 * 60 * 60   // 14日保持
    private let minIntervalSec: TimeInterval = 10 * 60        // 10分間隔で記録（書き込み抑制）

    private init() {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("AIMacOptimizer", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("health_history.json")
        load()
    }

    /// スナップショットを記録（前回から10分未満なら何もしない）
    func record(memUsedPercent: Double, swapMB: Double, diskFreePercent: Double, loadAvg1: Double) {
        if let last = snapshots.last, Date().timeIntervalSince(last.date) < minIntervalSec { return }
        // 値が未取得（全0）なら記録しない
        if memUsedPercent <= 0 && diskFreePercent <= 0 { return }

        snapshots.append(HealthSnapshot(
            date: Date(),
            memUsedPercent: memUsedPercent,
            swapMB: swapMB,
            diskFreePercent: diskFreePercent,
            loadAvg1: loadAvg1
        ))
        // 古いものを間引き
        let cutoff = Date().addingTimeInterval(-maxAgeSec)
        snapshots.removeAll { $0.date < cutoff }
        save()
    }

    /// 直近 hours 時間ぶんのスナップショット
    func recent(hours: Double) -> [HealthSnapshot] {
        let cutoff = Date().addingTimeInterval(-hours * 3600)
        return snapshots.filter { $0.date >= cutoff }
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([HealthSnapshot].self, from: data) else { return }
        snapshots = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(snapshots) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
