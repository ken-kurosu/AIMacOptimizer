import Foundation

/// A recorded snapshot of app usage at a point in time
struct UsageSnapshot: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let hour: Int               // 0-23, for time-of-day patterns
    let dayOfWeek: Int          // 1=Sun, 7=Sat
    let appName: String
    let memoryMB: Double
    let wasOptimized: Bool      // Did the user choose to optimize this?

    init(appName: String, memoryMB: Double, wasOptimized: Bool = false) {
        self.id = UUID()
        self.timestamp = Date()
        let calendar = Calendar.current
        self.hour = calendar.component(.hour, from: timestamp)
        self.dayOfWeek = calendar.component(.weekday, from: timestamp)
        self.appName = appName
        self.memoryMB = memoryMB
        self.wasOptimized = wasOptimized
    }
}

/// Learned pattern for an app: when it's typically used and when it's idle
struct AppUsageProfile: Codable {
    let appName: String
    var activeHours: Set<Int>           // Hours when app is actively used (0-23)
    var averageMemoryMB: Double
    var timesOptimized: Int             // How many times user chose to optimize this
    var timesIgnored: Int               // How many times user declined optimization
    var lastSeen: Date

    /// Confidence score that this app is idle right now (0.0 - 1.0)
    func idleConfidence(atHour hour: Int) -> Double {
        // If user has never optimized this app, low confidence
        guard timesOptimized + timesIgnored > 0 else { return 0.3 }

        var score = 0.0

        // Factor 1: Is this outside active hours?
        if !activeHours.contains(hour) {
            score += 0.4
        }

        // Factor 2: User optimization history
        let totalInteractions = Double(timesOptimized + timesIgnored)
        let optimizeRate = Double(timesOptimized) / totalInteractions
        score += optimizeRate * 0.4

        // Factor 3: Memory usage (higher = more likely to benefit)
        if averageMemoryMB > 500 {
            score += 0.2
        } else if averageMemoryMB > 200 {
            score += 0.1
        }

        return min(score, 1.0)
    }
}

/// Schedule preference for automatic optimization
struct OptimizationSchedule: Codable {
    var enabled: Bool = false
    var intervalMinutes: Int = 60       // Check every N minutes
    var onlyWhenIdle: Bool = true       // Only optimize when Mac is idle
    var quietHoursStart: Int = 23       // Don't optimize during quiet hours
    var quietHoursEnd: Int = 7
    var maxAutoActions: Int = 3         // Max items to auto-optimize per run

    func isQuietHour(_ hour: Int) -> Bool {
        if quietHoursStart < quietHoursEnd {
            return hour >= quietHoursStart && hour < quietHoursEnd
        } else {
            return hour >= quietHoursStart || hour < quietHoursEnd
        }
    }
}
