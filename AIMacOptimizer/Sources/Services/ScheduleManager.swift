import Foundation
import UserNotifications

/// Manages scheduled automatic optimization
final class ScheduleManager: ObservableObject {
    static let shared = ScheduleManager()

    @Published var schedule: OptimizationSchedule
    @Published var lastAutoRun: Date?
    @Published var nextAutoRun: Date?
    @Published var isAutoRunning = false

    private var timer: Timer?
    private let learner = PatternLearner.shared
    /// ワンショットのプロセス/メモリ取得専用（監視ループ startMonitoring は呼ばない）
    private let procSource = ProcessMonitor()
    private let optimizer = MemoryOptimizer()
    private let scheduleKey = "ai_mac_optimizer_schedule"

    private init() {
        // Load saved schedule
        if let data = UserDefaults.standard.data(forKey: scheduleKey),
           let saved = try? JSONDecoder().decode(OptimizationSchedule.self, from: data) {
            self.schedule = saved
        } else {
            self.schedule = OptimizationSchedule()
        }

        if schedule.enabled {
            startSchedule()
        }
    }

    // MARK: - Schedule Control

    func enableSchedule(_ enabled: Bool) {
        schedule.enabled = enabled
        saveSchedule()

        if enabled {
            startSchedule()
            requestNotificationPermission()
        } else {
            stopSchedule()
        }
    }

    func updateInterval(_ minutes: Int) {
        schedule.intervalMinutes = minutes
        saveSchedule()
        if schedule.enabled {
            stopSchedule()
            startSchedule()
        }
    }

    func setOnlyWhenIdle(_ value: Bool) {
        schedule.onlyWhenIdle = value
        saveSchedule()
    }

    /// 学習用にプロセスを一度だけ記録する（スケジュール有効時のみ、低頻度で呼ぶ）。
    /// パネル非表示中でも学習を進めるためのワンショット取得。
    func recordLearningSnapshot() {
        let procs = procSource.fetchOnce().processes
        learner.recordSnapshot(processes: procs)
    }

    private func startSchedule() {
        stopSchedule()
        let interval = TimeInterval(schedule.intervalMinutes * 60)
        nextAutoRun = Date().addingTimeInterval(interval)

        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.runAutoOptimization()
            }
        }
    }

    private func stopSchedule() {
        timer?.invalidate()
        timer = nil
        nextAutoRun = nil
    }

    // MARK: - Auto Optimization

    private func runAutoOptimization() async {
        let hour = Calendar.current.component(.hour, from: Date())

        // Check quiet hours
        guard !schedule.isQuietHour(hour) else {
            print("Skipping auto-optimization: quiet hours")
            return
        }

        // Check if Mac is idle (no user input for 5+ minutes)
        if schedule.onlyWhenIdle {
            let idleTime = getSystemIdleTime()
            guard idleTime > 300 else { // 5 minutes
                print("Skipping auto-optimization: user is active")
                return
            }
        }

        await MainActor.run { isAutoRunning = true }

        // ワンショットで現在のプロセス/メモリを取得（パネル非表示中でも動くよう監視ループには依存しない）
        let snap = procSource.fetchOnce()
        // 学習ベースの提案（profiles 読み取りはメインで、データ競合を避ける）
        let suggestions = await MainActor.run {
            learner.getSmartSuggestions(processes: snap.processes, systemMemory: snap.memory)
        }

        // 実際に解放されたメモリを測るため実行前の空きを記録
        let freeBefore = optimizer.currentFreeMemoryMB()

        // 過去に3回以上手動最適化した、かつ現在アイドル確度の高いアプリだけを自動終了
        var actionsExecuted = 0
        for suggestion in suggestions.prefix(schedule.maxAutoActions) where suggestion.type == .quitApp {
            let appName = suggestion.title
                .replacingOccurrences(of: "[高確度] ", with: "")
                .replacingOccurrences(of: "[中確度] ", with: "")
                .replacingOccurrences(of: " を終了", with: "")

            let eligible = await MainActor.run { () -> Bool in
                guard let profile = learner.profiles[appName] else { return false }
                return profile.timesOptimized > 2 && profile.idleConfidence(atHour: hour) > 0.7
            }
            if eligible {
                let outcome = await suggestion.action(suggestion.detailItems)
                if outcome.succeeded {
                    actionsExecuted += 1
                    await MainActor.run { learner.recordOptimized(appName: appName) }
                }
            }
        }
        // RAMパージは行わない（非rootで失敗し、空き指標にもほぼ反映されないため）

        // 実行後、メモリ返却が反映されるまで少し待ってから実測（推定ではなく実際の解放量を報告）
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        let freedMB = actionsExecuted > 0 ? max(0, optimizer.currentFreeMemoryMB() - freeBefore) : 0

        await MainActor.run {
            lastAutoRun = Date()
            nextAutoRun = Date().addingTimeInterval(TimeInterval(schedule.intervalMinutes * 60))
            isAutoRunning = false
        }

        // Notify user if actions were taken（実測値で通知）
        if actionsExecuted > 0 {
            let freedText = freedMB >= 1 ? "約\(Int(freedMB))MBを解放しました" : "メモリを整理しました"
            sendNotification(
                title: "自動最適化を実行しました",
                body: "\(actionsExecuted)件のアプリを終了し、\(freedText)。"
            )
        }
    }

    // MARK: - System Idle Time

    private func getSystemIdleTime() -> TimeInterval {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(
            kIOMainPortDefault,
            IOServiceMatching("IOHIDSystem"),
            &iterator
        ) == KERN_SUCCESS else { return 0 }

        let entry = IOIteratorNext(iterator)
        defer {
            IOObjectRelease(iterator)
            IOObjectRelease(entry)
        }

        var unmanagedDict: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &unmanagedDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = unmanagedDict?.takeRetainedValue() as? [String: Any],
              let idleNS = dict["HIDIdleTime"] as? Int64
        else { return 0 }

        return TimeInterval(idleNS) / 1_000_000_000 // Convert nanoseconds to seconds
    }

    // MARK: - Notifications

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil // Deliver immediately
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Persistence

    private func saveSchedule() {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        UserDefaults.standard.set(data, forKey: scheduleKey)
    }
}
