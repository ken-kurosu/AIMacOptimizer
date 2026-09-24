import AppKit

/// アプリごとの「最後に前面化(アクティブ化)された時刻」を記録する常駐トラッカー。
///
/// 「メモリ使用量の多いアプリ」を終了候補として出す際、
/// 「今まさに使っている(＝直近でアクティブだった)アプリ」を候補から外すために使う。
/// フォアグラウンド判定(frontmostApplication)だけでは「さっきまで使っていて今は裏だが、
/// すぐ戻るアプリ」を守れないため、didActivateApplicationNotificationを購読して
/// bundleID→最終アクティブ時刻を保持する。
final class AppActivityTracker {
    static let shared = AppActivityTracker()

    private var lastActive: [String: Date] = [:]
    private let lock = NSLock()
    private var started = false

    private init() {}

    /// アプリ起動時に一度だけ呼ぶ。以後、アクティブ化イベントを購読して時刻を更新する。
    func start() {
        guard !started else { return }
        started = true

        // 起動時点で前面のアプリを最終アクティブとして記録
        if let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier {
            record(bundle)
        }

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               let bundle = app.bundleIdentifier {
                self?.record(bundle)
            }
        }
    }

    private func record(_ bundleID: String) {
        lock.lock(); defer { lock.unlock() }
        lastActive[bundleID] = Date()
    }

    /// 最後にアクティブだった時刻からの経過分。記録が無ければ nil。
    func minutesSinceActive(_ bundleID: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        guard let date = lastActive[bundleID] else { return nil }
        return Date().timeIntervalSince(date) / 60.0
    }

    /// 直近 minutes 分以内にアクティブだったか（記録が無ければ false）。
    func wasActiveWithin(minutes: Double, bundleID: String) -> Bool {
        guard let m = minutesSinceActive(bundleID) else { return false }
        return m <= minutes
    }
}
