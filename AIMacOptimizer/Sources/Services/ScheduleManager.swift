import Foundation
import UserNotifications

/// Manages scheduled automatic optimization
final class ScheduleManager: ObservableObject {
    @Published var schedule: OptimizationSchedule
    @Published var lastAutoRun: Date?
    @Published var nextAutoRun: Date?
    @Published var isAutoRunning = false

    private var timer: Timer?
    private let monitor: ProcessMonitor
    private let learner: PatternLearner
    private let optimizer = MemoryOptimizer()
    private let scheduleKey = "ai_mac_optimizer_schedule"

    init(monitor: ProcessMonitor, learner: PatternLearner) {
        self.monitor = monitor
        self.learner = learner

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

        // @Published（monitor/learner）はメインで読み、データ競合を避ける
        let (snapMemory, suggestions): (SystemMemoryInfo, [OptimizationSuggestion]) = await MainActor.run {
            (monitor.systemMemory,
             learner.getSmartSuggestions(processes: monitor.processes, systemMemory: monitor.systemMemory))
        }

        // Only auto-execute high-confidence, safe actions (up to maxAutoActions)
        var actionsExecuted = 0
        var freedMB: Double = 0

        for suggestion in suggestions.prefix(schedule.maxAutoActions) {
            // Only auto-close apps that user has optimized before
            if suggestion.type == .quitApp {
                let appName = suggestion.title
                    .replacingOccurrences(of: "[高確度] ", with: "")
                    .replacingOccurrences(of: "[中確度] ", with: "")
                    .replacingOccurrences(of: " を終了", with: "")

                // プロファイル判定（@Published profiles 読み取り）はメインで
                let eligible = await MainActor.run { () -> Bool in
                    guard let profile = learner.profiles[appName] else { return false }
                    return profile.timesOptimized > 2 && profile.idleConfidence(atHour: hour) > 0.7
                }
                if eligible {
                    let outcome = await suggestion.action(suggestion.detailItems)
                    if outcome.succeeded {
                        actionsExecuted += 1
                        freedMB += suggestion.estimatedSavingMB
                        await MainActor.run { learner.recordOptimized(appName: appName) }
                    }
                }
            }
        }

        // Always try RAM purge if memory is high
        if snapMemory.severity == .high {
            let purged = await optimizer.purgeRAM()
            if purged {
                actionsExecuted += 1
                freedMB += snapMemory.totalMB * 0.05
            }
        }

        await MainActor.run {
            lastAutoRun = Date()
            nextAutoRun = Date().addingTimeInterval(TimeInterval(schedule.intervalMinutes * 60))
            isAutoRunning = false
        }

        // Notify user if actions were taken
        if actionsExecuted > 0 {
            sendNotification(
                title: "自動最適化を実行しました",
                body: "\(actionsExecuted)件の最適化を実行し、約\(Int(freedMB))MBを解放しました。"
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
