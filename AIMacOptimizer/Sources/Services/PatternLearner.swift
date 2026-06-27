import Foundation

/// AI-powered pattern learning engine that improves suggestions over time
final class PatternLearner: ObservableObject {

    @Published var profiles: [String: AppUsageProfile] = [:]

    private let storageKey = "ai_mac_optimizer_patterns"
    private var snapshots: [UsageSnapshot] = []
    private let maxSnapshots = 10000

    init() {
        loadProfiles()
    }

    // MARK: - Recording

    /// Record current app states for learning
    func recordSnapshot(processes: [ProcessMemoryInfo]) {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: Date())

        for process in processes where !process.isSystemProcess && process.memoryMB > 50 {
            let snapshot = UsageSnapshot(
                appName: process.name,
                memoryMB: process.memoryMB
            )
            snapshots.append(snapshot)

            // Update or create profile
            updateProfile(appName: process.name, memoryMB: process.memoryMB, hour: hour)
        }

        // Trim old snapshots
        if snapshots.count > maxSnapshots {
            snapshots = Array(snapshots.suffix(maxSnapshots / 2))
        }
    }

    /// Record that user accepted an optimization suggestion
    func recordOptimized(appName: String) {
        if var profile = profiles[appName] {
            profile.timesOptimized += 1
            profiles[appName] = profile
            saveProfiles()
        }
    }

    /// Record that user declined/ignored a suggestion
    func recordIgnored(appName: String) {
        if var profile = profiles[appName] {
            profile.timesIgnored += 1
            profiles[appName] = profile
            saveProfiles()
        }
    }

    // MARK: - Analysis

    /// Get apps that are likely idle right now, sorted by confidence
    func getIdleApps(currentProcesses: [ProcessMemoryInfo]) -> [(app: ProcessMemoryInfo, confidence: Double)] {
        let hour = Calendar.current.component(.hour, from: Date())

        return currentProcesses
            .filter { !$0.isSystemProcess && $0.memoryMB > 100 }
            .compactMap { process -> (ProcessMemoryInfo, Double)? in
                guard let profile = profiles[process.name] else { return nil }
                let confidence = profile.idleConfidence(atHour: hour)
                return confidence > 0.5 ? (process, confidence) : nil
            }
            .sorted { $0.1 > $1.1 }
    }

    /// Get personalized suggestions based on learned patterns
    func getSmartSuggestions(
        processes: [ProcessMemoryInfo],
        systemMemory: SystemMemoryInfo
    ) -> [OptimizationSuggestion] {
        let idleApps = getIdleApps(currentProcesses: processes)
        let optimizer = MemoryOptimizer()

        return idleApps.prefix(5).map { app, confidence in
            let confidenceText = confidence > 0.8 ? "高確度" : "中確度"
            return OptimizationSuggestion(
                type: .quitApp,
                title: "[\(confidenceText)] \(app.name) を終了",
                description: "\(app.memoryFormatted) 使用中。学習データに基づき、現在は使用されていない可能性が高いです。",
                estimatedSavingMB: app.memoryMB,
                action: { _ in
                    ActionOutcome(succeeded: optimizer.quitApp(name: app.name))
                }
            )
        }
    }

    // MARK: - Profile Management

    private func updateProfile(appName: String, memoryMB: Double, hour: Int) {
        if var profile = profiles[appName] {
            profile.activeHours.insert(hour)
            // Running average
            profile.averageMemoryMB = (profile.averageMemoryMB + memoryMB) / 2
            profile.lastSeen = Date()
            profiles[appName] = profile
        } else {
            profiles[appName] = AppUsageProfile(
                appName: appName,
                activeHours: [hour],
                averageMemoryMB: memoryMB,
                timesOptimized: 0,
                timesIgnored: 0,
                lastSeen: Date()
            )
        }
    }

    // MARK: - Persistence

    private func saveProfiles() {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    private func loadProfiles() {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let loaded = try? JSONDecoder().decode([String: AppUsageProfile].self, from: data)
        else { return }
        profiles = loaded
    }

    /// Clear all learned data
    func resetLearning() {
        profiles.removeAll()
        snapshots.removeAll()
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
